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
    var previous: coins = 0;
    if (lookup.isFound) {
        previous = lookup.loadValue();
    }
    storage.refundCredits.set(beneficiary, (previous + amount) as coins);
}

fun addPayoutCredit(mutate storage: AuctionManagerStorage, beneficiary: address, amount: coins) {
    val lookup = storage.payoutCredits.get(beneficiary);
    var previous: coins = 0;
    if (lookup.isFound) {
        previous = lookup.loadValue();
    }
    storage.payoutCredits.set(beneficiary, (previous + amount) as coins);
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessageToAuctionManager.fromSlice(in.body);

    match (msg) {
        SetPayoutAddressesV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw AuctionManagerErrors.NotFromOwner;
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (!storage.payoutConfigLocked) throw AuctionManagerErrors.InvalidPayoutConfiguration;
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
                treasury != storage.ownerAddress &&
                securityFund != storage.ownerAddress
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            storage.payoutAddresses.set(0, treasury);
            storage.payoutAddresses.set(1, securityFund);
            storage.save();
        }

        CreateAuctionV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw AuctionManagerErrors.NotFromOwner;
            assert (msg.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                storage.payoutAddresses.exists(0) && storage.payoutAddresses.exists(1)
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            assert (in.valueCoins >= AUCTION_V1_MIN_CREATE_OVERHEAD) throw AuctionManagerErrors.InsufficientAttachedValue;
            assert (msg.itemIndex == storage.nextItemIndex) throw AuctionManagerErrors.ItemIndexOutOfSequence;
            assert (msg.startingBid > 0 && msg.minimumBidStep > 0) throw AuctionManagerErrors.InvalidAuctionParameters;
            assert (msg.endTime > blockchain.now()) throw AuctionManagerErrors.InvalidAuctionParameters;

            val auctionId = storage.nextItemIndex;
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
            storage.nextItemIndex += 1;
            storage.payoutConfigLocked = true;
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

            var minimum: coins = auction.startingBid;
            if (auction.highestBidder != null) {
                minimum = (auction.highestBid + auction.minimumBidStep) as coins;
            }
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

            assert (auction.itemIndex == storage.nextMintItemIndex) throw AuctionManagerErrors.ItemIndexOutOfSequence;

            if (auction.highestBidder == null || auction.highestBid == 0) {
                val skipQueryId = storage.nextQueryId;
                storage.nextQueryId += 1;
                auction.status = AUCTION_V1_CLOSED_NO_BIDS;
                auction.mintQueryId = skipQueryId;
                storage.nextMintItemIndex += 1;
                storage.auctions.set(msg.auctionId, auction);
                storage.save();

                val skip = createMessage({
                    bounce: BounceMode.RichBounce,
                    dest: storage.collectionAddress,
                    value: AUCTION_V1_MIN_CREATE_OVERHEAD,
                    body: SkipNftItemIndexV12 { queryId: skipQueryId, itemIndex: auction.itemIndex },
                });
                skip.send(SEND_MODE_PAY_FEES_SEPARATELY);
                return;
            }
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
            val auctionLookup = storage.auctions.get(msg.itemIndex);
            assert (auctionLookup.isFound) throw AuctionManagerErrors.InvalidMintConfirmation;
            var auction = auctionLookup.loadValue();
            assert (auction.mintQueryId == msg.queryId) throw AuctionManagerErrors.InvalidMintConfirmation;
            assert (msg.nftAddress != address.fromWorkchainAndHash(0, 0)) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_CLOSED_PAID) {
                sendMintAck(storage.collectionAddress, msg.queryId, msg.itemIndex);
                return;
            }
            assert (auction.status == AUCTION_V1_WAITING_FOR_MINT) throw AuctionManagerErrors.InvalidAuctionState;
            assert (auction.highestBidder != null && auction.highestBid > 0) throw AuctionManagerErrors.InvalidAuctionState;

            val treasuryLookup = storage.payoutAddresses.get(0);
            val securityLookup = storage.payoutAddresses.get(1);
            assert (treasuryLookup.isFound && securityLookup.isFound) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            val treasury = treasuryLookup.loadValue();
            val securityFund = securityLookup.loadValue();

            auction.status = AUCTION_V1_CLOSED_PAID;
            storage.auctions.set(msg.itemIndex, auction);
            storage.nextMintItemIndex += 1;
            storage.save();

            val treasuryShare = (auction.highestBid * 30 / 100) as coins;
            val securityShare = (auction.highestBid * 20 / 100) as coins;
            val creatorShare = (auction.highestBid - treasuryShare - securityShare) as coins;
            var queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(msg.itemIndex, storage.ownerAddress, creatorShare, queryId);

            queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(msg.itemIndex, treasury, treasuryShare, queryId);

            queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(msg.itemIndex, securityFund, securityShare, queryId);
            sendMintAck(storage.collectionAddress, msg.queryId, msg.itemIndex);
        }

        NftItemDeploymentFailedV12 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.collectionAddress) throw AuctionManagerErrors.NotFromCollection;
            val auctionLookup = storage.auctions.get(msg.itemIndex);
            assert (auctionLookup.isFound) throw AuctionManagerErrors.InvalidMintConfirmation;
            var auction = auctionLookup.loadValue();
            assert (auction.mintQueryId == msg.queryId) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_CLOSED_MINT_FAILED) {
                sendMintAck(storage.collectionAddress, msg.queryId, msg.itemIndex);
                return;
            }
            assert (auction.status == AUCTION_V1_WAITING_FOR_MINT) throw AuctionManagerErrors.InvalidAuctionState;

            auction.status = AUCTION_V1_CLOSED_MINT_FAILED;
            storage.auctions.set(msg.itemIndex, auction);
            storage.nextMintItemIndex += 1;
            storage.save();

            if (auction.highestBidder != null && auction.highestBid > 0) {
                val refundQueryId = storage.nextQueryId;
                storage.nextQueryId += 1;
                storage.save();
                sendRefund(msg.itemIndex, auction.highestBidder!, auction.highestBid, refundQueryId);
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
        addRefundCredit(mutate storage, transfer.beneficiary, transfer.amount);
        storage.save();
        return;
    }

    if (originalOpcode == 0x54474108) {
        val transfer = PayoutTransferV1.fromCell(bounced.originalBody);
        addPayoutCredit(mutate storage, transfer.beneficiary, transfer.amount);
        storage.save();
        return;
    }

    if (originalOpcode == 0x54474909) {
        val skip = SkipNftItemIndexV12.fromCell(bounced.originalBody);
        val auctionLookup = storage.auctions.get(skip.itemIndex);
        if (!auctionLookup.isFound) {
            return;
        }
        var auction = auctionLookup.loadValue();
        if (
            auction.status == AUCTION_V1_CLOSED_NO_BIDS &&
            auction.mintQueryId == skip.queryId &&
            storage.nextMintItemIndex == skip.itemIndex + 1
        ) {
            auction.status = AUCTION_V1_ACTIVE;
            auction.mintQueryId = 0;
            storage.nextMintItemIndex -= 1;
            storage.auctions.set(skip.itemIndex, auction);
            storage.save();
        }
        return;
    }

    if (originalOpcode == 0x54474903) {
        val deploy = DeployNftV12.fromCell(bounced.originalBody);
        val auctionLookup = storage.auctions.get(deploy.itemIndex);
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
            storage.auctions.set(deploy.itemIndex, auction);
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
    if (!lookup.isFound) {
        return 0;
    }
    return lookup.loadValue();
}

get fun get_payout_credit(beneficiary: address): coins {
    val storage = lazy AuctionManagerStorage.load();
    val lookup = storage.payoutCredits.get(beneficiary);
    if (!lookup.isFound) {
        return 0;
    }
    return lookup.loadValue();
}
