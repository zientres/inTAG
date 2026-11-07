import "@stdlib/strings"
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
    | RetryMintNoticeV1
    | ClaimRefundV1
    | ClaimPayoutV1
    | SetPayoutAddressesV1
    | WithdrawTreasuryV1
    | NftItemDeploymentConfirmedV12
    | NftItemDeploymentFailedV12

fun sendRefund(
    auctionId: uint64,
    beneficiary: address,
    amount: coins,
    queryId: uint64,
) {
    val refundMessage = createMessage({
        bounce: BounceMode.RichBounce,
        dest: beneficiary,
        value: amount,
        body: RefundTransferV1 { queryId, auctionId, beneficiary, amount },
    });
    refundMessage.send(SEND_MODE_PAY_FEES_SEPARATELY);
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
    val payoutMessage = createMessage({
        bounce: BounceMode.RichBounce,
        dest: beneficiary,
        value: amount,
        body: PayoutTransferV1 { queryId, auctionId, beneficiary, amount },
    });
    payoutMessage.send(SEND_MODE_PAY_FEES_SEPARATELY);
}

fun sendMintAck(collectionAddress: address, queryId: uint64, itemIndex: uint64) {
    val ackMessage = createMessage({
        bounce: BounceMode.NoBounce,
        dest: collectionAddress,
        value: 0,
        body: NftItemDeploymentAckV12 { queryId, itemIndex },
    });
    ackMessage.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun addRefundCredit(mutate storage: AuctionManagerStorage, beneficiary: address, amount: coins) {
    val lookup = storage.refundCredits.get(beneficiary);
    var previous: coins = 0;
    if (lookup.isFound) {
        previous = lookup.loadValue();
    }
    storage.refundCredits.set(beneficiary, (previous + amount) as coins);
    storage.lockedFunds = (storage.lockedFunds + amount) as coins;
}

fun addPayoutCredit(mutate storage: AuctionManagerStorage, beneficiary: address, amount: coins) {
    val lookup = storage.payoutCredits.get(beneficiary);
    var previous: coins = 0;
    if (lookup.isFound) {
        previous = lookup.loadValue();
    }
    storage.payoutCredits.set(beneficiary, (previous + amount) as coins);
    storage.lockedFunds = (storage.lockedFunds + amount) as coins;
}

fun onInternalMessage(in: InMessage) {
    val message = lazy AllowedMessageToAuctionManager.fromSlice(in.body);

    match (message) {
        SetPayoutAddressesV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (
                in.senderAddress == storage.ownerAddress
            ) throw AuctionManagerErrors.NotFromOwner;
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                !storage.payoutConfigLocked
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            assert (
                message.securityFundAddress != null
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            val securityFund = message.securityFundAddress;
            assert (isValidManagerAddress(securityFund)) throw AuctionManagerErrors.InvalidAddress;
            assert (
                securityFund != storage.ownerAddress
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            storage.payoutAddresses.set(1, securityFund);
            storage.save();
        }

        CreateAuctionV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (
                in.senderAddress == storage.ownerAddress
            ) throw AuctionManagerErrors.NotFromOwner;
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                storage.payoutAddresses.exists(0) && storage.payoutAddresses.exists(1)
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_CREATE_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            assert (
                message.itemIndex == storage.nextItemIndex
            ) throw AuctionManagerErrors.ItemIndexOutOfSequence;
            assert (
                message.startingBid > 0 && message.minimumBidStep > 0
            ) throw AuctionManagerErrors.InvalidAuctionParameters;
            assert (
                message.endTime > blockchain.now()
            ) throw AuctionManagerErrors.InvalidAuctionParameters;
            val plateLength = message.plate.calculateLength();
            val metadataContentLength = message.metadataContent.calculateLength();
            assert (
                plateLength > 0 && plateLength <= AUCTION_V1_MAX_PLATE_BYTES &&
                metadataContentLength > 0 &&
                metadataContentLength <= AUCTION_V1_MAX_METADATA_CONTENT_BYTES
            ) throw AuctionManagerErrors.InvalidAuctionParameters;

            val auctionId = storage.nextItemIndex;
            val auction: AuctionV1 = {
                itemIndex: message.itemIndex,
                plate: message.plate,
                metadataContent: message.metadataContent,
                startingBid: message.startingBid,
                minimumBidStep: message.minimumBidStep,
                endTime: message.endTime,
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
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            val lookup = storage.auctions.get(message.auctionId);
            assert (lookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            var auction = lookup.loadValue();
            assert (
                auction.status == AUCTION_V1_ACTIVE
            ) throw AuctionManagerErrors.AuctionAlreadyEnded;
            assert (blockchain.now() < auction.endTime) throw AuctionManagerErrors.BidAfterDeadline;
            assert (
                in.valueCoins >= message.bidAmount + AUCTION_V1_MIN_BID_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;

            var minimum: coins = auction.startingBid;
            if (auction.highestBidder != null) {
                minimum = (auction.highestBid + auction.minimumBidStep) as coins;
            }
            assert (message.bidAmount >= minimum) throw AuctionManagerErrors.BidTooLow;

            val previousBidder = auction.highestBidder;
            val previousBid = auction.highestBid;
            auction.highestBid = message.bidAmount;
            auction.highestBidder = in.senderAddress;
            storage.auctions.set(message.auctionId, auction);
            storage.lockedFunds = (storage.lockedFunds + message.bidAmount - previousBid) as coins;
            storage.save();

            if (previousBidder != null && previousBid > 0) {
                val refundQueryId = storage.nextQueryId;
                storage.nextQueryId += 1;
                storage.save();
                sendRefund(message.auctionId, previousBidder, previousBid, refundQueryId);
            }
        }

        FinishAuctionV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_FINISH_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            val lookup = storage.auctions.get(message.auctionId);
            assert (lookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            var auction = lookup.loadValue();
            assert (
                auction.status == AUCTION_V1_ACTIVE
            ) throw AuctionManagerErrors.AuctionAlreadyEnded;
            assert (blockchain.now() >= auction.endTime) throw AuctionManagerErrors.AuctionNotEnded;

            assert (
                auction.itemIndex == storage.nextMintItemIndex
            ) throw AuctionManagerErrors.ItemIndexOutOfSequence;

            if (auction.highestBidder == null || auction.highestBid == 0) {
                val skipQueryId = storage.nextQueryId;
                storage.nextQueryId += 1;
                auction.status = AUCTION_V1_CLOSED_NO_BIDS;
                auction.mintQueryId = skipQueryId;
                storage.nextMintItemIndex += 1;
                storage.auctions.set(message.auctionId, auction);
                storage.save();

                val skip = createMessage({
                    bounce: BounceMode.RichBounce,
                    dest: storage.collectionAddress,
                    value: AUCTION_V1_MIN_CREATE_OVERHEAD,
                    body: SkipNftItemIndexV12 {
                        queryId: skipQueryId,
                        itemIndex: auction.itemIndex,
                    },
                });
                skip.send(SEND_MODE_PAY_FEES_SEPARATELY);
                return;
            }
            val mintQueryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            auction.status = AUCTION_V1_WAITING_FOR_MINT;
            auction.mintQueryId = mintQueryId;
            storage.auctions.set(message.auctionId, auction);
            storage.save();

            val deploy = createMessage({
                bounce: BounceMode.RichBounce,
                dest: storage.collectionAddress,
                value: AUCTION_V1_COLLECTION_DEPLOY_VALUE,
                body: DeployNftV12 {
                    queryId: mintQueryId,
                    itemIndex: auction.itemIndex,
                    attachTonAmount: AUCTION_V1_ITEM_DEPLOY_VALUE,
                    ownerAddress: auction.highestBidder,
                    content: auction.metadataContent,
                },
            });
            deploy.send(SEND_MODE_PAY_FEES_SEPARATELY);
        }

        RetryMintNoticeV1 => {
            val storage = lazy AuctionManagerStorage.load();
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_CREATE_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            val lookup = storage.auctions.get(message.auctionId);
            assert (lookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            val auction = lookup.loadValue();
            assert (
                auction.status == AUCTION_V1_WAITING_FOR_MINT ||
                auction.status == AUCTION_V1_CLOSED_PAID ||
                auction.status == AUCTION_V1_CLOSED_MINT_FAILED
            ) throw AuctionManagerErrors.InvalidAuctionState;
            assert (auction.mintQueryId != 0) throw AuctionManagerErrors.InvalidMintConfirmation;

            val retry = createMessage({
                bounce: BounceMode.RichBounce,
                dest: storage.collectionAddress,
                value: AUCTION_V1_MIN_CREATE_OVERHEAD,
                body: RetryNftItemDeploymentNoticeV12 {
                    queryId: auction.mintQueryId,
                    itemIndex: auction.itemIndex,
                },
            });
            retry.send(SEND_MODE_PAY_FEES_SEPARATELY);
        }

        NftItemDeploymentConfirmedV12 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (
                in.senderAddress == storage.collectionAddress
            ) throw AuctionManagerErrors.NotFromCollection;
            val auctionLookup = storage.auctions.get(message.itemIndex);
            assert (auctionLookup.isFound) throw AuctionManagerErrors.InvalidMintConfirmation;
            var auction = auctionLookup.loadValue();
            assert (
                auction.mintQueryId == message.queryId
            ) throw AuctionManagerErrors.InvalidMintConfirmation;
            assert (
                message.nftAddress != address.fromWorkchainAndHash(0, 0)
            ) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_CLOSED_PAID) {
                sendMintAck(storage.collectionAddress, message.queryId, message.itemIndex);
                return;
            }
            assert (
                auction.status == AUCTION_V1_WAITING_FOR_MINT
            ) throw AuctionManagerErrors.InvalidAuctionState;
            assert (
                auction.highestBidder != null && auction.highestBid > 0
            ) throw AuctionManagerErrors.InvalidAuctionState;

            val securityLookup = storage.payoutAddresses.get(1);
            assert (securityLookup.isFound) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            val securityFund = securityLookup.loadValue();

            auction.status = AUCTION_V1_CLOSED_PAID;
            storage.auctions.set(message.itemIndex, auction);
            storage.nextMintItemIndex += 1;
            storage.save();

            val treasuryShare = (auction.highestBid * 30 / 100) as coins;
            val securityShare = (auction.highestBid * 20 / 100) as coins;
            val creatorShare = (auction.highestBid - treasuryShare - securityShare) as coins;
            storage.lockedFunds = (storage.lockedFunds - auction.highestBid) as coins;
            storage.treasuryBalance = (storage.treasuryBalance + treasuryShare) as coins;
            var queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(message.itemIndex, storage.ownerAddress, creatorShare, queryId);

            queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(message.itemIndex, securityFund, securityShare, queryId);
            sendMintAck(storage.collectionAddress, message.queryId, message.itemIndex);
        }

        NftItemDeploymentFailedV12 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (
                in.senderAddress == storage.collectionAddress
            ) throw AuctionManagerErrors.NotFromCollection;
            val auctionLookup = storage.auctions.get(message.itemIndex);
            assert (auctionLookup.isFound) throw AuctionManagerErrors.InvalidMintConfirmation;
            var auction = auctionLookup.loadValue();
            assert (
                auction.mintQueryId == message.queryId
            ) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_CLOSED_MINT_FAILED) {
                sendMintAck(storage.collectionAddress, message.queryId, message.itemIndex);
                return;
            }
            assert (
                auction.status == AUCTION_V1_WAITING_FOR_MINT
            ) throw AuctionManagerErrors.InvalidAuctionState;

            auction.status = AUCTION_V1_CLOSED_MINT_FAILED;
            storage.lockedFunds = (storage.lockedFunds - auction.highestBid) as coins;
            storage.auctions.set(message.itemIndex, auction);
            storage.nextMintItemIndex += 1;
            storage.save();

            if (auction.highestBidder != null && auction.highestBid > 0) {
                val refundQueryId = storage.nextQueryId;
                storage.nextQueryId += 1;
                storage.save();
                sendRefund(
                    message.itemIndex,
                    auction.highestBidder,
                    auction.highestBid,
                    refundQueryId,
                );
            }
            sendMintAck(storage.collectionAddress, message.queryId, message.itemIndex);
        }

        ClaimRefundV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_CLAIM_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            val lookup = storage.refundCredits.get(in.senderAddress);
            assert (lookup.isFound) throw AuctionManagerErrors.NoRefundAvailable;
            val amount = lookup.loadValue();
            assert (amount > 0) throw AuctionManagerErrors.NoRefundAvailable;
            storage.refundCredits.delete(in.senderAddress);
            storage.lockedFunds = (storage.lockedFunds - amount) as coins;
            val queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendRefund(0, in.senderAddress, amount, queryId);
        }

        WithdrawTreasuryV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (in.senderAddress == storage.ownerAddress) throw AuctionManagerErrors.NotFromOwner;
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (message.amount > 0) throw AuctionManagerErrors.InvalidTreasuryWithdrawal;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_WITHDRAW_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            assert (
                message.amount <= storage.treasuryBalance
            ) throw AuctionManagerErrors.InsufficientTreasuryBalance;
            val requiredBalance = (
                storage.lockedFunds + message.amount + AUCTION_V1_MIN_OPERATIONAL_RESERVE
            ) as coins;
            assert (
                contract.getOriginalBalance() >= requiredBalance
            ) throw AuctionManagerErrors.InsufficientManagerBalance;

            storage.treasuryBalance = (storage.treasuryBalance - message.amount) as coins;
            val transferQueryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            val withdrawal = createMessage({
                bounce: BounceMode.RichBounce,
                dest: storage.ownerAddress,
                value: message.amount,
                body: TreasuryWithdrawalTransferV1 {
                    queryId: transferQueryId,
                    amount: message.amount,
                },
            });
            withdrawal.send(SEND_MODE_PAY_FEES_SEPARATELY);
        }

        ClaimPayoutV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_CLAIM_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            val lookup = storage.payoutCredits.get(in.senderAddress);
            assert (lookup.isFound) throw AuctionManagerErrors.NoPayoutAvailable;
            val amount = lookup.loadValue();
            assert (amount > 0) throw AuctionManagerErrors.NoPayoutAvailable;
            storage.payoutCredits.delete(in.senderAddress);
            storage.lockedFunds = (storage.lockedFunds - amount) as coins;
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

    if (originalOpcode == 0x5447410C) {
        val transfer = TreasuryWithdrawalTransferV1.fromCell(bounced.originalBody);
        storage.treasuryBalance = (storage.treasuryBalance + transfer.amount) as coins;
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
            auction.status == AUCTION_V1_CLOSED_NO_BIDS && auction.mintQueryId == skip.queryId &&
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
            auction.status == AUCTION_V1_WAITING_FOR_MINT && auction.mintQueryId == deploy.queryId
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

get fun get_treasury_balance(): coins {
    val storage = lazy AuctionManagerStorage.load();
    return storage.treasuryBalance;
}

get fun get_payout_credit(beneficiary: address): coins {
    val storage = lazy AuctionManagerStorage.load();
    val lookup = storage.payoutCredits.get(beneficiary);
    if (!lookup.isFound) {
        return 0;
    }
    return lookup.loadValue();
}
