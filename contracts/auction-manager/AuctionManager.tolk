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
    | NftItemIndexSkippedV12

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

fun isAllowedRussianPlateLetter(mutate value: slice): bool {
    val first = value.loadUint(8);
    val second = value.loadUint(8);
    return first == 0xD0 && (
        second == 0x90 || second == 0x92 || second == 0x95 ||
        second == 0x9A || second == 0x9C || second == 0x9D ||
        second == 0x9E || second == 0xA0 || second == 0xA1 ||
        second == 0xA2 || second == 0xA3 || second == 0xA5
    );
}

fun isRussianPlateDigit(mutate value: slice): bool {
    val digit = value.loadUint(8);
    return digit >= 0x30 && digit <= 0x39;
}

fun isValidRussianPlate(plate: string): bool {
    if (plate.depth() != 0) {
        return false;
    }
    val byteLength = plate.calculateLength();
    if (byteLength != 11 && byteLength != 12) {
        return false;
    }

    var value = plate.beginParse();
    if (!isAllowedRussianPlateLetter(mutate value)) {
        return false;
    }
    if (!isRussianPlateDigit(mutate value) || !isRussianPlateDigit(value) || !isRussianPlateDigit(value)) {
        return false;
    }
    if (!isAllowedRussianPlateLetter(value) || !isAllowedRussianPlateLetter(value)) {
        return false;
    }
    if (!isRussianPlateDigit(value) || !isRussianPlateDigit(value)) {
        return false;
    }
    if (byteLength == 12 && !isRussianPlateDigit(value)) {
        return false;
    }
    return value.isEmpty();
}

fun buildOnchainPlateMetadata(plate: string): cell {
    val name = StringBuilder.create().append("TagitalSpace — ").append(plate).build();
    val description = StringBuilder.create()
        .append("Digital license plate collectible from TagitalSpace. Russian plate: ")
        .append(plate)
        .build();
    val attributes = StringBuilder.create()
        .append("[{\"trait_type\":\"Country\",\"value\":\"Russia\"},{\"trait_type\":\"Plate\",\"value\":\"")
        .append(plate)
        .append("\"}]")
        .build();
    val imageData = StringBuilder.create()
        .append("<svg xmlns='http://www.w3.org/2000/svg' width='1200' height='720' viewBox='0 0 1200 720'><rect width='1200' height='720' fill='#071426'/><rect x='80' y='180' width='1040' height='360' rx='24' fill='white'/><text x='600' y='390' text-anchor='middle' font-family='Arial' font-size='96' font-weight='700' fill='#071426'>")
        .append(plate)
        .append("</text><text x='600' y='610' text-anchor='middle' font-family='Arial' font-size='28' letter-spacing='6' fill='#a8b8cc'>TAGITALSPACE</text></svg>")
        .build();

    var dict: map<uint256, string_prefixed0x> = [];
    dict.set("name".sha256(), name.prefixWith00());
    dict.set("description".sha256(), description.prefixWith00());
    dict.set("attributes".sha256(), attributes.prefixWith00());
    dict.set("image".sha256(), "https://zientres.github.io/inTAG/logo.png".prefixWith00());
    dict.set("image_data".sha256(), imageData.prefixWith00());
    return beginCell()
        .storeUint(0, 8)
        .storeDict(dict.toLowLevelDict())
        .endCell();
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
            storage.securityFundAddress = securityFund;
            storage.save();
        }

        CreateAuctionV1 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (
                storage.securityFundAddress != null
            ) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_CREATE_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            assert (
                message.startingBid > 0 && message.minimumBidStep > 0
            ) throw AuctionManagerErrors.InvalidAuctionParameters;
            assert (
                message.endTime > blockchain.now() &&
                message.endTime <= blockchain.now() + AUCTION_V1_MAX_DURATION_SECONDS
            ) throw AuctionManagerErrors.InvalidAuctionParameters;
            val plateLength = message.plate.calculateLength();
            assert (
                plateLength > 0 && plateLength <= AUCTION_V1_MAX_PLATE_BYTES &&
                isValidRussianPlate(message.plate)
            ) throw AuctionManagerErrors.InvalidAuctionParameters;

            val plateKey = StringBuilder.create().append("RU|").append(message.plate).build().hash();
            var plateRegistry = storage.plateRegistry.load();
            val plateLookup = plateRegistry.plateToAuctionId.get(plateKey);
            assert (!plateLookup.isFound) throw AuctionManagerErrors.AuctionAlreadyExists;

            val auctionId = storage.nextItemIndex;
            val auction: AuctionV1 = {
                itemIndex: auctionId,
                plate: message.plate,
                startingBid: message.startingBid,
                minimumBidStep: message.minimumBidStep,
                endTime: message.endTime,
                highestBid: 0,
                highestBidder: null,
                status: AUCTION_V1_ACTIVE,
                mintQueryId: 0,
            };
            storage.auctions.set(auctionId, auction);
            plateRegistry.plateToAuctionId.set(plateKey, auctionId);
            storage.plateRegistry = plateRegistry.toCell();
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
                auction.status = AUCTION_V1_WAITING_FOR_SKIP;
                auction.mintQueryId = skipQueryId;
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
                    content: buildOnchainPlateMetadata(auction.plate),
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
                auction.status == AUCTION_V1_WAITING_FOR_SKIP ||
                auction.status == AUCTION_V1_CLOSED_PAID ||
                auction.status == AUCTION_V1_CLOSED_MINT_FAILED
            ) throw AuctionManagerErrors.InvalidAuctionState;
            assert (auction.mintQueryId != 0) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_WAITING_FOR_SKIP) {
                val retrySkip = createMessage({
                    bounce: BounceMode.RichBounce,
                    dest: storage.collectionAddress,
                    value: AUCTION_V1_MIN_CREATE_OVERHEAD,
                    body: SkipNftItemIndexV12 {
                        queryId: auction.mintQueryId,
                        itemIndex: auction.itemIndex,
                    },
                });
                retrySkip.send(SEND_MODE_PAY_FEES_SEPARATELY);
            } else {
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
        }

        NftItemIndexSkippedV12 => {
            var storage = lazy AuctionManagerStorage.load();
            assert (
                in.senderAddress == storage.collectionAddress
            ) throw AuctionManagerErrors.NotFromCollection;
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;

            val auctionLookup = storage.auctions.get(message.itemIndex);
            assert (auctionLookup.isFound) throw AuctionManagerErrors.InvalidAuctionId;
            var auction = auctionLookup.loadValue();
            assert (
                auction.mintQueryId == message.queryId
            ) throw AuctionManagerErrors.InvalidMintConfirmation;

            if (auction.status == AUCTION_V1_CLOSED_NO_BIDS) {
                return;
            }
            assert (
                auction.status == AUCTION_V1_WAITING_FOR_SKIP
            ) throw AuctionManagerErrors.InvalidAuctionState;
            assert (
                auction.itemIndex == storage.nextMintItemIndex
            ) throw AuctionManagerErrors.ItemIndexOutOfSequence;

            auction.status = AUCTION_V1_CLOSED_NO_BIDS;
            val plateKey = StringBuilder.create().append("RU|").append(auction.plate).build().hash();
            var plateRegistry = storage.plateRegistry.load();
            plateRegistry.plateToAuctionId.delete(plateKey);
            storage.plateRegistry = plateRegistry.toCell();
            storage.auctions.set(message.itemIndex, auction);
            storage.nextMintItemIndex += 1;
            storage.save();
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

            assert (storage.securityFundAddress != null) throw AuctionManagerErrors.InvalidPayoutConfiguration;
            val securityFund = storage.securityFundAddress;

            auction.status = AUCTION_V1_CLOSED_PAID;
            storage.auctions.set(message.itemIndex, auction);
            storage.nextMintItemIndex += 1;
            storage.save();

            val treasuryShare = (auction.highestBid * 30 / 100) as coins;
            val securityShare = (auction.highestBid * 20 / 100) as coins;
            val ownerShare = (auction.highestBid - treasuryShare - securityShare) as coins;
            storage.lockedFunds = (storage.lockedFunds - auction.highestBid) as coins;
            storage.treasuryBalance = (storage.treasuryBalance + treasuryShare) as coins;
            var queryId = storage.nextQueryId;
            storage.nextQueryId += 1;
            storage.save();
            sendPayout(message.itemIndex, storage.ownerAddress, ownerShare, queryId);

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
            val plateKey = StringBuilder.create().append("RU|").append(auction.plate).build().hash();
            storage.plateToAuctionId.delete(plateKey);
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
            assert (
                in.senderAddress == storage.ownerAddress
            ) throw AuctionManagerErrors.NotFromOwner;
            assert (message.queryId != 0) throw AuctionManagerErrors.InvalidQueryId;
            assert (message.amount > 0) throw AuctionManagerErrors.InvalidTreasuryWithdrawal;
            assert (
                in.valueCoins >= AUCTION_V1_MIN_WITHDRAW_OVERHEAD
            ) throw AuctionManagerErrors.InsufficientAttachedValue;
            assert (
                message.amount <= storage.treasuryBalance
            ) throw AuctionManagerErrors.InsufficientTreasuryBalance;
            val requiredBalance = (storage.lockedFunds + message.amount +
                AUCTION_V1_MIN_OPERATIONAL_RESERVE) as coins;
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
        // Keep the auction in WAITING_FOR_SKIP. RetryMintNoticeV1 resends
        // the same idempotent request; the collection can replay its ACK.
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

get fun get_plate_status(plateHash: uint256): int {
    val storage = lazy AuctionManagerStorage.load();
    val plateLookup = storage.plateToAuctionId.get(plateHash);
    if (!plateLookup.isFound) {
        return 0;
    }
    val auctionLookup = storage.auctions.get(plateLookup.loadValue());
    if (!auctionLookup.isFound) {
        return 0;
    }
    val auction = auctionLookup.loadValue();
    if (auction.status == AUCTION_V1_CLOSED_PAID) {
        return 2;
    }
    return 1;
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
