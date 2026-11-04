import "@contracts/nft-v1.1/errors"
import "@contracts/nft-v1.1/fees-management"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"

contract NftItem {
    author: "The Tolk Team"
    version: "1.1"
    description: "Standard NFT Item. TEP-62 and TEP-64 compliant"
    incomingMessages: AllowedMessageToNftItem
    storage: NftItemStorage
    storageAtDeployment: NftItemStorageNotInitialized
}

type AllowedMessageToNftItem =
    | AskToChangeOwnership
    | RequestStaticData

fun onInternalMessage(in: InMessage) {
    var loadingStorage = NftItemStorage.startLoading();
    if (loadingStorage.isNotInitialized()) {
        assert (
            in.senderAddress == loadingStorage.collectionAddress
        ) throw Errors.NotFromCollection;

        // using a message from collection, convert "uninitialized" to "initialized" state
        val initParams = NftItemInitAtDeployment.fromSlice(in.body);
        val storage: NftItemStorage = {
            itemIndex: loadingStorage.itemIndex,
            collectionAddress: loadingStorage.collectionAddress,
            ownerAddress: initParams.ownerAddress,
            content: initParams.content,
        };
        storage.save();
        return;
    }

    var storage = loadingStorage.endLoading();

    val message = lazy AllowedMessageToNftItem.fromSlice(in.body);

    match (message) {
        AskToChangeOwnership => {
            assert (in.senderAddress == storage.ownerAddress) throw Errors.NotFromOwner;

            // validate Either format: bit 0 = inline (any payload follows),
            // bit 1 = ref (must be exactly 1 bit + 1 ref)
            val (fwdBits, fwdRefs) = message.forwardPayload.remainingBitsAndRefsCount();
            assert (fwdBits != 0) throw Errors.IncorrectForwardPayload;
            if (message.forwardPayload.preloadUint(1) != 0) {
                assert (fwdBits == 1 && fwdRefs == 1) throw Errors.IncorrectForwardPayload;
            }
            assert (message.newOwnerAddress.getWorkchain() == BASECHAIN) throw Errors.InvalidWorkchain;

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

            // base nft-v1.1 spends fixed amount of gas, will not check for response
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
                // why ever, in FunC implementation, item index was encoded as 256-bit (not 64-bit),
                // do the same here to pass FunC tests;
                // but since a response becomes too long (64 + 256 + address), the compiler will create a ref;
                // force the compiler not to create a ref, because it's guaranteed that with
                // value (coins) = 0 it will nevertheless fit into a message cell directly
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

        else => {
            // ignore empty messages, "wrong opcode" for others
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
