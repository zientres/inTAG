import "@contracts/nft-v1.1/errors"
import "@contracts/nft-v1.1/fees-management"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/messages"

contract NftItemV12 {
    author: "TagitalSpace"
    version: "1.2"
    description: "TEP-62 and TEP-64 NFT item with collection initialization confirmation"
    incomingMessages: AllowedMessageToNftItemV12
    storage: NftItemStorage
    storageAtDeployment: NftItemStorageNotInitialized
}

type AllowedMessageToNftItemV12 =
    | AskToChangeOwnership
    | RequestStaticData

fun onInternalMessage(in: InMessage) {
    var loadingStorage = NftItemStorage.startLoading();
    if (loadingStorage.isNotInitialized()) {
        assert (
            in.senderAddress == loadingStorage.collectionAddress
        ) throw Errors.NotFromCollection;

        val initParams = NftItemInitAtDeploymentV12.fromSlice(in.body);
        assert (initParams.itemIndex == loadingStorage.itemIndex) throw Errors.InvalidItemIndex;

        val storage: NftItemStorage = {
            itemIndex: loadingStorage.itemIndex,
            collectionAddress: loadingStorage.collectionAddress,
            ownerAddress: initParams.ownerAddress,
            content: initParams.content,
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
    val msg = lazy AllowedMessageToNftItemV12.fromSlice(in.body);

    match (msg) {
        AskToChangeOwnership => {
            assert (in.senderAddress == storage.ownerAddress) throw Errors.NotFromOwner;

            val (fwdBits, fwdRefs) = msg.forwardPayload.remainingBitsAndRefsCount();
            assert (fwdBits != 0) throw Errors.IncorrectForwardPayload;
            if (msg.forwardPayload.preloadUint(1) != 0) {
                assert (fwdBits == 1 && fwdRefs == 1) throw Errors.IncorrectForwardPayload;
            }
            assert (msg.newOwnerAddress.getWorkchain() == BASECHAIN) throw Errors.InvalidWorkchain;

            val fwdFee = in.originalForwardFee;
            var restAmount = contract.getOriginalBalance() - MIN_TONS_FOR_STORAGE;
            if (msg.forwardTonAmount != 0) {
                restAmount -= (msg.forwardTonAmount + fwdFee);
            }
            if (msg.sendExcessesTo != null) {
                assert (
                    msg.sendExcessesTo.getWorkchain() == BASECHAIN
                ) throw Errors.InvalidWorkchain;
                restAmount -= fwdFee;
            }

            assert (restAmount >= 0) throw Errors.TooSmallRestAmount;

            if (msg.forwardTonAmount != 0) {
                val ownershipMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: msg.newOwnerAddress,
                    value: msg.forwardTonAmount,
                    body: NotificationForNewOwner {
                        queryId: msg.queryId,
                        oldOwnerAddress: storage.ownerAddress,
                        payload: msg.forwardPayload,
                    },
                });
                ownershipMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }
            if (msg.sendExcessesTo != null) {
                val excessesMsg = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: msg.sendExcessesTo,
                    value: restAmount,
                    body: ReturnExcessesBack { queryId: msg.queryId },
                });
                excessesMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
            }

            storage.ownerAddress = msg.newOwnerAddress;
            storage.save();
        }

        RequestStaticData => {
            val respondMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: in.senderAddress,
                value: 0,
                body: UnsafeBodyNoRef {
                    forceInline: ResponseStaticData {
                        queryId: msg.queryId,
                        itemIndex: storage.itemIndex as uint256,
                        collectionAddress: storage.collectionAddress,
                    },
                },
            });
            respondMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        else => {
            assert (in.body.isEmpty()) throw 0xFFFF;
        }
    }
}

get fun get_nft_data(): NftDataReply {
    var loadingStorage = NftItemStorage.startLoading();
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
