import "@contracts/nft-v1.1/errors"
import "@contracts/nft-v1.1/fees-management"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/messages"
import "@contracts/nft-v1.2/types"

contract NftItemV12 {
    author: "TagitalSpace"
    version: "1.2"
    description: "TEP-62 and TEP-64 NFT item with collection initialization confirmation"
    incomingMessages: AllowedMessageToNftItemV12
    storage: NftItemV12Storage
    storageAtDeployment: NftItemV12StorageNotInitialized
}

type AllowedMessageToNftItemV12 =
    | AskToChangeOwnership
    | RequestStaticData
    | RequestNftItemConfirmationV12

fun onInternalMessage(in: InMessage) {
    var loadingStorage = NftItemV12Storage.startLoading();
    if (loadingStorage.isNotInitialized()) {
        assert (
            in.senderAddress == loadingStorage.collectionAddress
        ) throw Errors.NotFromCollection;

        val initParams = NftItemInitAtDeploymentV12.fromSlice(in.body);
        assert (initParams.itemIndex == loadingStorage.itemIndex) throw Errors.InvalidItemIndex;

        val storage: NftItemV12Storage = {
            itemIndex: loadingStorage.itemIndex,
            collectionAddress: loadingStorage.collectionAddress,
            ownerAddress: initParams.ownerAddress,
            content: initParams.content,
            initQueryId: initParams.queryId,
        };
        storage.save();

        val confirmation = createMessage({
            bounce: BounceMode.NoBounce,
            dest: loadingStorage.collectionAddress,
            value: 0,
            body: NftItemInitializedV12 {
                queryId: initParams.queryId,
                itemIndex: initParams.itemIndex,
            },
        });
        confirmation.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        return;
    }

    var storage = loadingStorage.endLoading();
    val message = lazy AllowedMessageToNftItemV12.fromSlice(in.body);

    match (message) {
        AskToChangeOwnership => {
            assert (in.senderAddress == storage.ownerAddress) throw Errors.NotFromOwner;

            val (fwdBits, fwdRefs) = message.forwardPayload.remainingBitsAndRefsCount();
            assert (fwdBits != 0) throw Errors.IncorrectForwardPayload;
            if (message.forwardPayload.preloadUint(1) != 0) {
                assert (fwdBits == 1 && fwdRefs == 1) throw Errors.IncorrectForwardPayload;
            }
            assert (
                message.newOwnerAddress.getWorkchain() == BASECHAIN
            ) throw Errors.InvalidWorkchain;

            val fwdFee = in.originalForwardFee;
            var restAmount = contract.getOriginalBalance() - MIN_TONS_FOR_STORAGE;
            if (message.forwardTonAmount != 0) {
                restAmount -= (message.forwardTonAmount + fwdFee);
            }
            if (message.sendExcessesTo != null) {
                assert (
                    message.sendExcessesTo.getWorkchain() == BASECHAIN
                ) throw Errors.InvalidWorkchain;
                restAmount -= fwdFee;
            }

            assert (restAmount >= 0) throw Errors.TooSmallRestAmount;

            if (message.forwardTonAmount != 0) {
                val ownershipMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: message.newOwnerAddress,
                    value: message.forwardTonAmount,
                    body: NotificationForNewOwner {
                        queryId: message.queryId,
                        oldOwnerAddress: storage.ownerAddress,
                        payload: message.forwardPayload,
                    },
                });
                ownershipMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }
            if (message.sendExcessesTo != null) {
                val excessesMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: message.sendExcessesTo,
                    value: restAmount,
                    body: ReturnExcessesBack { queryId: message.queryId },
                });
                excessesMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }

            storage.ownerAddress = message.newOwnerAddress;
            storage.save();
        }

        RequestStaticData => {
            val respondMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: in.senderAddress,
                value: 0,
                body: UnsafeBodyNoRef {
                    forceInline: ResponseStaticData {
                        queryId: message.queryId,
                        itemIndex: storage.itemIndex as uint256,
                        collectionAddress: storage.collectionAddress,
                    },
                },
            });
            respondMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        RequestNftItemConfirmationV12 => {
            assert (in.senderAddress == storage.collectionAddress) throw Errors.NotFromCollection;
            assert (message.itemIndex == storage.itemIndex) throw Errors.InvalidItemIndex;
            assert (message.queryId == storage.initQueryId) throw Errors.NotFromCollection;

            val confirmation = createMessage({
                bounce: BounceMode.NoBounce,
                dest: storage.collectionAddress,
                value: 0,
                body: NftItemInitializedV12 {
                    queryId: storage.initQueryId,
                    itemIndex: storage.itemIndex,
                },
            });
            confirmation.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        else => {
            assert (in.body.isEmpty()) throw 0xFFFF;
        }
    }
}

get fun get_nft_data(): NftDataReply {
    var loadingStorage = NftItemV12Storage.startLoading();
    if (loadingStorage.isNotInitialized()) {
        return {
            isInitialized: false,
            itemIndex: loadingStorage.itemIndex,
            collectionAddress: loadingStorage.collectionAddress,
        };
    }

    val storage = loadingStorage.endLoading();
    return {
        isInitialized: true,
        itemIndex: storage.itemIndex,
        collectionAddress: storage.collectionAddress,
        ownerAddress: storage.ownerAddress,
        content: storage.content,
    };
}
