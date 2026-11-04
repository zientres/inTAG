import "@contracts/auction-manager/errors"
import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"
import "@contracts/nft-v1.2/messages"

contract AuctionManager {
    author: "TagitalSpace"
    version: "1.0"
    description: "Auction escrow and verified NFT mint manager"
    incomingMessages: AllowedMessageToAuctionManager
    storage: AuctionManagerStorage
}

type AllowedMessageToAuctionManager =
    | CreateAuctionV1
    | PlaceBidV1
    | FinishAuctionV1
    | ClaimRefundV1
    | ClaimPayoutV1
    | SetPayoutAddressesV1
    | NftItemDeploymentConfirmedV12
    | NftItemDeploymentFailedV12

fun sendRefund(
    auctionId: uint64,
    beneficiary: address,
    amount: coins,
    queryId: uint64,
) {
    val message = createMessage({
        bounce: BounceMode.RichBounce,
        dest: beneficiary,
        value: amount,
        body: RefundTransferV1 { queryId, auctionId, beneficiary, amount },
    });
    message.send(SEND_MODE_PAY_FEES_SEPARATELY);
}

fun sendPayout(
    auctionId: uint64,
    beneficiary: address,
    amount: coins,
    queryId: uint64,
) {
    if (amount == 0) {
        return;
    }
    val message = createMessage({
        bounce: BounceMode.RichBounce,
        dest: beneficiary,
        value: amount,
        body: PayoutTransferV1 { queryId, auctionId, beneficiary, amount },
    });
    message.send(SEND_MODE_PAY_FEES_SEPARATELY);
}

fun sendMintAck(collectionAddress: address, queryId: uint64, itemIndex: uint64) {
    val message = createMessage({
        bounce: BounceMode.NoBounce,
        dest: collectionAddress,
        value: 0,
        body: NftItemDeploymentAckV12 { queryId, itemIndex },
    });
    message.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun addRefundCredit(mutate storage: AuctionManagerStorage, beneficiary: address, amount: coins) {
    val lookup = storage.refundCredits.get(beneficiary);
    val previous = if (lookup.isFound) lookup.loadValue() else 0;
    storage.refundCredits.set(beneficiary, previous + amount);
}

fun addPayoutCredit(mutate storage: AuctionManagerStorage, beneficiary: address, amount: coins) {
    val lookup = storage.payoutCredits.get(beneficiary);
    val previous = if (lookup.isFound) lookup.loadValue() else 0;
    storage.payoutCredits.set(beneficiary, previous + amount);
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessageToAuctionManager.fromSlice(in.body);

    match (msg) {
        SetPayoutAddressesV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw AuctionManagerErrors.NotFromOwner;
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                msg.treasuryAddress != null && msg.securityFundAddress != null
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            val treasury = msg.treasuryAddress!;
            val securityFund = msg.securityFundAddress!;
            assert (
                isValidManagerAddress(treasury) && isValidManagerAddress(securityFund)
            ) throw AuctionManagerErrors.InvalidAddress;
            assert (
                treasury != securityFund &&
                treasury != storage.creatorAddress &&
                securityFund != storage.creatorAddress
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            storage.treasuryAddress = treasury;
            storage.securityFundAddress = securityFund;
            storage.save();
        }

        CreateAuctionV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw AuctionManagerErrors.NotFromOwner;
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                storage.treasuryAddress != null && storage.securityFundAddress != null
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            assert (in.valueCoins >= AUCTION_V1_MIN_CREATE_OVERHEAD) throw AuctionManagerErrors.InsufficientAttachedValue;
            assert (msg.itemIndex == storage.nextItemIndex) throw AuctionManagerErrors.ItemIndexOutOfSequence;
            assert (msg.startingBid > 0 && msg.minimumBidStep > 0) throw AuctionManagerErrors.InvalidAuctionParameters;
            assert (msg.endTime > blockchain.now()) throw AuctionManagerErrors.InvalidAuctionParameters;
            assert (msg.plate != "" && msg.metadataContent != "") throw AuctionManagerErrors.InvalidAuctionParameters;

            val auctionId = storage.nextAuctionId;
            val auction: AuctionV1 = {
                itemIndex: msg.itemIndex,
                plate: msg.plate,
                metadataContent: msg.metadataContent,
                startingBid: msg.startingBid,
                minimumBidStep: msg.minimumBidStep,
                endTime: msg.endTime,
                highestBid: 0,
                highestBidder: null,
                status: AUCTION_V1_ACTIVE,
                mintQueryId: 0,
            };
            storage.auctions.set(auctionId, auction);
            storage.itemToAuction.set(msg.itemIndex, auctionId);
            storage.nextAuctionId += 1;
            storage.nextItemIndex += 1;
            storage.save();
        }

        PlaceBidV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            val lookup = storage.auctions.get(msg.auctionId);
            assert (lookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            var auction = lookup.loadValue();
            assert (auction.status == AUCTION_V1_ACTIVE) throw AuctionManagerErrors.AuctionAlreadyEnded;
            assert (blockchain.now() < auction.endTime) throw AuctionManagerErrors.BidAfterDeadline;
            assert (
                in.valueCoins >= msg.bidAmount + AUCTION_V1_MIN_BID_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;

            val minimum = if (auction.highestBidder == null) {
                auction.startingBid
            } else {
                auction.highestBid + auction.minimumBidStep
            };
            assert (msg.bidAmount >= minimum) throw AuctionManagerErrors.BidTooLow;

            val previousBidder = auction.highestBidder;
            val previousBid = auction.highestBid;
            auction.highestBid = msg.bidAmount;
            auction.highestBidder = in.senderAddress;
            storage.auctions.set(msg.auctionId, auction);
            storage.save();

            if (previousBidder != null && previousBid > 0) {
                val refundQueryId = storage.nextQueryId;
                storage.nextQueryId += 1;
                storage.save();
                sendRefund(msg.auctionId, previousBidder!, previousBid, refundQueryId);
            }
        }

        FinishAuctionV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (in.valueCoins >= AUCTION_V1_MIN_FINISH_OVERHEAD) throw AuctionManagerErrors.InsufficientAttachedValue;
            val lookup = storage.auctions.get(msg.auctionId);
            assert (lookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            var auction = lookup.loadValue();
            assert (auction.status == AUCTION_V1_ACTIVE) throw AuctionManagerErrors.AuctionAlreadyEnded;
            assert (blockchain.now() >= auction.endTime) throw AuctionManagerErrors.AuctionNotEnded;

            if (auction.highestBidder == null || auction.highestBid == 0) {
                auction.status = AUCTION_V1_CLOSED_NO_BIDS;
                storage.auctions.set(msg.auctionId, auction);
                storage.save();
                return;
            }

            assert (auction.itemIndex == storage.nextMintItemIndex) throw AuctionManagerErrors.ItemIndexOutOfSequence;
            val mintQueryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            auction.status = AUCTION_V1_WAITING_FOR_MINT;
            auction.mintQueryId = mintQueryId;
            storage.auctions.set(msg.auctionId, auction);
            storage.save();

            val deploy = createMessage({
                bounce: BounceMode.RichBounce,
                dest: storage.collectionAddress,
                value: AUCTION_V1_COLLECTION_DEPLOY_VALUE,
                body: DeployNftV12 {
                    queryId: mintQueryId,
                    itemIndex: auction.itemIndex,
                    attachTonAmount: AUCTION_V1_ITEM_DEPLOY_VALUE,
                    ownerAddress: auction.highestBidder!,
                    content: auction.metadataContent,
                },
            });
            deploy.send(SEND_MODE_PAY_FEES_SEPARATELY);
        }

        NftItemDeploymentConfirmedV12 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.collectionAddress) throw AuctionManagerErrors.NotFromCollection;
            val itemLookup = storage.itemToAuction.get(msg.itemIndex);
            assert (itemLookup.isFound) throw AuctionManagerErrors.InvalidMintConfirmation;
            val auctionId = itemLookup.loadValue();
            val auctionLookup = storage.auctions.get(auctionId);
            assert (auctionLookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            var auction = auctionLookup.loadValue();
            assert (auction.mintQueryId == msg.queryId) throw AuctionManagerErrors.InvalidMintConfirmation;
            assert (msg.nftAddress != address.fromWorkchainAndHash(0, 0)) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_CLOSED_PAID) {
                sendMintAck(storage.collectionAddress, msg.queryId, msg.itemIndex);
                return;
            }
            assert (auction.status == AUCTION_V1_WAITING_FOR_MINT) throw AuctionManagerErrors.InvalidAuctionState;
            assert (auction.highestBidder != null && auction.highestBid > 0) throw AuctionManagerErrors.InvalidAuctionState;
            assert (
                storage.treasuryAddress != null && storage.securityFundAddress != null
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;

            auction.status = AUCTION_V1_CLOSED_PAID;
            storage.auctions.set(auctionId, auction);
            storage.nextMintItemIndex += 1;
            storage.save();

            val treasury = storage.treasuryAddress!;
            val securityFund = storage.securityFundAddress!;
            val treasuryShare = auction.highestBid * 30 / 100;
            val securityShare = auction.highestBid * 20 / 100;
            val creatorShare = auction.highestBid - treasuryShare - securityShare;
            var queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();

            sendPayout(auctionId, storage.creatorAddress, creatorShare, queryId);
            queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(auctionId, treasury, treasuryShare, queryId);
            queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(auctionId, securityFund, securityShare, queryId);
            sendMintAck(storage.collectionAddress, msg.queryId, msg.itemIndex);
        }

        NftItemDeploymentFailedV12 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.collectionAddress) throw AuctionManagerErrors.NotFromCollection;
            val itemLookup = storage.itemToAuction.get(msg.itemIndex);
            assert (itemLookup.isFound) throw AuctionManagerErrors.InvalidMintConfirmation;
            val auctionId = itemLookup.loadValue();
            val auctionLookup = storage.auctions.get(auctionId);
            assert (auctionLookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            var auction = auctionLookup.loadValue();
            assert (auction.mintQueryId == msg.queryId) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_CLOSED_MINT_FAILED) {
                sendMintAck(storage.collectionAddress, msg.queryId, msg.itemIndex);
                return;
            }
            assert (auction.status == AUCTION_V1_WAITING_FOR_MINT) throw AuctionManagerErrors.InvalidAuctionState;

            auction.status = AUCTION_V1_CLOSED_MINT_FAILED;
            storage.auctions.set(auctionId, auction);
            storage.nextMintItemIndex += 1;
            storage.save();

            if (auction.highestBidder != null && auction.highestBid > 0) {
                val refundQueryId = storage.nextQueryId;
                storage.nextQueryId += 1;
                storage.save();
                sendRefund(auctionId, auction.highestBidder!, auction.highestBid, refundQueryId);
            }
            sendMintAck(storage.collectionAddress, msg.queryId, msg.itemIndex);
        }

        ClaimRefundV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            val lookup = storage.refundCredits.get(in.senderAddress);
            assert (lookup.isFound) throw AuctionManagerErrors.NoRefundAvailable;
            val amount = lookup.loadValue();
            assert (amount > 0) throw AuctionManagerErrors.NoRefundAvailable;
            storage.refundCredits.delete(in.senderAddress);
            val queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendRefund(0, in.senderAddress, amount, queryId);
        }

        ClaimPayoutV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            val lookup = storage.payoutCredits.get(in.senderAddress);
            assert (lookup.isFound) throw AuctionManagerErrors.NoPayoutAvailable;
            val amount = lookup.loadValue();
            assert (amount > 0) throw AuctionManagerErrors.NoPayoutAvailable;
            storage.payoutCredits.delete(in.senderAddress);
            val queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(0, in.senderAddress, amount, queryId);
        }

        else => {
            assert (in.body.isEmpty()) throw 0xFFFF;
        }
    }
}

fun onBouncedMessage(in: InMessageBounced) {
    val bounced = lazy RichBounceBody.fromSlice(in.bouncedBody);
    var originalBody = bounced.originalBody.beginParse();
    val originalOpcode = originalBody.loadUint(32);
    var storage = lazy AuctionManagerStorage.load();

    if (originalOpcode == 0x54474107) {
        val transfer = RefundTransferV1.fromCell(bounced.originalBody);
        if (!storage.processedBounces.exists(transfer.queryId)) {
            addRefundCredit(storage, transfer.beneficiary, transfer.amount);
            storage.processedBounces.set(transfer.queryId, true);
            storage.save();
        }
        return;
    }

    if (originalOpcode == 0x54474108) {
        val transfer = PayoutTransferV1.fromCell(bounced.originalBody);
        if (!storage.processedBounces.exists(transfer.queryId)) {
            addPayoutCredit(storage, transfer.beneficiary, transfer.amount);
            storage.processedBounces.set(transfer.queryId, true);
            storage.save();
        }
        return;
    }

    if (originalOpcode == 0x54474903) {
        val deploy = DeployNftV12.fromCell(bounced.originalBody);
        val itemLookup = storage.itemToAuction.get(deploy.itemIndex);
        if (!itemLookup.isFound) {
            return;
        }
        val auctionId = itemLookup.loadValue();
        val auctionLookup = storage.auctions.get(auctionId);
        if (!auctionLookup.isFound) {
            return;
        }
        var auction = auctionLookup.loadValue();
        if (
            auction.status == AUCTION_V1_WAITING_FOR_MINT &&
            auction.mintQueryId == deploy.queryId
        ) {
            auction.status = AUCTION_V1_ACTIVE;
            auction.mintQueryId = 0;
            storage.auctions.set(auctionId, auction);
            storage.save();
        }
    }
}

get fun get_auction(auctionId: uint64): AuctionV1? {
    val storage = lazy AuctionManagerStorage.load();
    val lookup = storage.auctions.get(auctionId);
    if (!lookup.isFound) {
        return null;
    }
    return lookup.loadValue();
}

get fun get_refund_credit(beneficiary: address): coins {
    val storage = lazy AuctionManagerStorage.load();
    val lookup = storage.refundCredits.get(beneficiary);
    return if (lookup.isFound) lookup.loadValue() else 0;
}

get fun get_payout_credit(beneficiary: address): coins {
    val storage = lazy AuctionManagerStorage.load();
    val lookup = storage.payoutCredits.get(beneficiary);
    return if (lookup.isFound) lookup.loadValue() else 0;
}
