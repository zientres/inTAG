import "@stdlib/strings"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/errors"
import "@contracts/nft-v1.2/messages"
import "@contracts/nft-v1.2/types"

contract NftCollectionV12 {
    author: "TagitalSpace"
    version: "1.2"
    description: "TEP-62 and TEP-64 collection with verified NFT deployment callbacks"
    incomingMessages: AllowedMessageToNftCollectionV12
    storage: NftCollectionV12Storage
}

type AllowedMessageToNftCollectionV12 =
    | RequestRoyaltyParams
    | DeployNftV12
    | NftItemInitializedV12
    | NftItemDeploymentAckV12
    | RetryNftItemDeploymentNoticeV12
    | ChangeCollectionAdmin

fun deployNftItemV12(
    itemIndex: uint64,
    nftItemCode: cell,
    attachTonAmount: coins,
    initParams: NftItemInitAtDeploymentV12,
) {
    val deployMsg = createMessage({
        bounce: BounceMode.RichBounce,
        dest: calcDeployedNftItemV12(itemIndex, contract.getAddress(), nftItemCode),
        value: attachTonAmount,
        body: initParams,
    });
    deployMsg.send(SEND_MODE_PAY_FEES_SEPARATELY);
}

fun notifyManagerOfSuccessfulDeployment(
    managerAddress: address,
    queryId: uint64,
    itemIndex: uint64,
    nftAddress: address,
) {
    val notification = createMessage({
        bounce: BounceMode.RichBounce,
        dest: managerAddress,
        value: 0,
        body: NftItemDeploymentConfirmedV12 { queryId, itemIndex, nftAddress },
    });
    notification.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun notifyManagerOfFailedDeployment(
    managerAddress: address,
    queryId: uint64,
    itemIndex: uint64,
    exitCode: int32,
) {
    val notification = createMessage({
        bounce: BounceMode.RichBounce,
        dest: managerAddress,
        value: 0,
        body: NftItemDeploymentFailedV12 { queryId, itemIndex, exitCode },
    });
    notification.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy AllowedMessageToNftCollectionV12.fromSlice(in.body);

    match (msg) {
        DeployNftV12 => {
            var storage = lazy NftCollectionV12Storage.load();
            assert (in.senderAddress == storage.adminAddress) throw NftV12Errors.NotFromAdmin;
            assert (msg.queryId != 0) throw NftV12Errors.InvalidDeploymentState;
            assert (msg.itemIndex == storage.nextItemIndex) throw NftV12Errors.InvalidItemIndex;
            assert (
                !storage.pendingDeployments.exists(msg.itemIndex)
            ) throw NftV12Errors.PendingDeploymentAlreadyExists;

            val itemAddress = calcDeployedNftItemV12(
                msg.itemIndex,
                contract.getAddress(),
                storage.nftItemCode,
            ).calculateAddress();

            val pending: PendingNftDeploymentV12 = {
                queryId: msg.queryId,
                managerAddress: in.senderAddress,
                itemAddress,
                status: NFT_V12_DEPLOYMENT_WAITING_FOR_ITEM,
                exitCode: 0,
            };
            storage.pendingDeployments.set(msg.itemIndex, pending);
            storage.nextItemIndex += 1;
            storage.save();

            deployNftItemV12(
                msg.itemIndex,
                storage.nftItemCode,
                msg.attachTonAmount,
                NftItemInitAtDeploymentV12 {
                    queryId: msg.queryId,
                    itemIndex: msg.itemIndex,
                    ownerAddress: msg.ownerAddress,
                    content: msg.content,
                },
            );
        }

        NftItemInitializedV12 => {
            var storage = lazy NftCollectionV12Storage.load();
            val expectedItemAddress = calcDeployedNftItemV12(
                msg.itemIndex,
                contract.getAddress(),
                storage.nftItemCode,
            ).calculateAddress();
            assert (
                in.senderAddress == expectedItemAddress
            ) throw NftV12Errors.NotFromExpectedNftItem;

            val lookup = storage.pendingDeployments.get(msg.itemIndex);
            assert (lookup.isFound) throw NftV12Errors.PendingDeploymentNotFound;
            var pending = lookup.loadValue();
            assert (pending.queryId == msg.queryId) throw NftV12Errors.InvalidDeploymentState;
            assert (
                pending.itemAddress == in.senderAddress
            ) throw NftV12Errors.NotFromExpectedNftItem;
            assert (
                pending.status == NFT_V12_DEPLOYMENT_WAITING_FOR_ITEM
            ) throw NftV12Errors.InvalidDeploymentState;

            pending.status = NFT_V12_DEPLOYMENT_READY_FOR_MANAGER;
            pending.exitCode = 0;
            storage.pendingDeployments.set(msg.itemIndex, pending);
            storage.save();

            notifyManagerOfSuccessfulDeployment(
                pending.managerAddress,
                pending.queryId,
                msg.itemIndex,
                pending.itemAddress,
            );
        }

        NftItemDeploymentAckV12 => {
            var storage = lazy NftCollectionV12Storage.load();
            val lookup = storage.pendingDeployments.get(msg.itemIndex);
            assert (lookup.isFound) throw NftV12Errors.PendingDeploymentNotFound;
            val pending = lookup.loadValue();
            assert (in.senderAddress == pending.managerAddress) throw NftV12Errors.NotFromManager;
            assert (pending.queryId == msg.queryId) throw NftV12Errors.InvalidDeploymentState;
            assert (
                pending.status == NFT_V12_DEPLOYMENT_READY_FOR_MANAGER ||
                pending.status == NFT_V12_DEPLOYMENT_FAILED
            ) throw NftV12Errors.DeploymentNoticeNotReady;
            storage.pendingDeployments.delete(msg.itemIndex);
            storage.save();
        }

        RetryNftItemDeploymentNoticeV12 => {
            val storage = lazy NftCollectionV12Storage.load();
            val lookup = storage.pendingDeployments.get(msg.itemIndex);
            assert (lookup.isFound) throw NftV12Errors.PendingDeploymentNotFound;
            val pending = lookup.loadValue();
            assert (in.senderAddress == pending.managerAddress) throw NftV12Errors.NotFromManager;
            assert (pending.queryId == msg.queryId) throw NftV12Errors.InvalidDeploymentState;

            if (pending.status == NFT_V12_DEPLOYMENT_WAITING_FOR_ITEM) {
                val retryItem = createMessage({
                    bounce: BounceMode.NoBounce,
                    dest: pending.itemAddress,
                    value: 0,
                    body: RequestNftItemConfirmationV12 {
                        queryId: pending.queryId,
                        itemIndex: msg.itemIndex,
                    },
                });
                retryItem.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
            } else if (pending.status == NFT_V12_DEPLOYMENT_READY_FOR_MANAGER) {
                notifyManagerOfSuccessfulDeployment(
                    pending.managerAddress,
                    pending.queryId,
                    msg.itemIndex,
                    pending.itemAddress,
                );
            } else {
                assert (
                    pending.status == NFT_V12_DEPLOYMENT_FAILED
                ) throw NftV12Errors.DeploymentNoticeNotReady;
                notifyManagerOfFailedDeployment(
                    pending.managerAddress,
                    pending.queryId,
                    msg.itemIndex,
                    pending.exitCode,
                );
            }
        }

        RequestRoyaltyParams => {
            val storage = lazy NftCollectionV12Storage.load();
            val respondMsg = createMessage({
                bounce: BounceMode.NoBounce,
                dest: in.senderAddress,
                value: 0,
                body: ResponseRoyaltyParams {
                    queryId: msg.queryId,
                    royaltyParams: storage.royaltyParams.load(),
                },
            });
            respondMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }

        ChangeCollectionAdmin => {
            var storage = lazy NftCollectionV12Storage.load();
            assert (in.senderAddress == storage.adminAddress) throw NftV12Errors.NotFromAdmin;
            storage.adminAddress = msg.newAdminAddress;
            storage.save();
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
    if (originalOpcode != 0x54474901) {
        // A bounced manager notification remains pending and can be retried by the manager.
        return;
    }

    val initParams = NftItemInitAtDeploymentV12.fromCell(bounced.originalBody);
    var storage = lazy NftCollectionV12Storage.load();
    val lookup = storage.pendingDeployments.get(initParams.itemIndex);
    if (!lookup.isFound) {
        return;
    }

    var pending = lookup.loadValue();
    if (
        in.senderAddress != pending.itemAddress || pending.queryId != initParams.queryId ||
        pending.status != NFT_V12_DEPLOYMENT_WAITING_FOR_ITEM
    ) {
        return;
    }

    pending.status = NFT_V12_DEPLOYMENT_FAILED;
    pending.exitCode = bounced.exitCode;
    storage.pendingDeployments.set(initParams.itemIndex, pending);
    storage.save();

    notifyManagerOfFailedDeployment(
        pending.managerAddress,
        pending.queryId,
        initParams.itemIndex,
        pending.exitCode,
    );
}

get fun get_collection_data(): CollectionDataReply {
    val storage = lazy NftCollectionV12Storage.load();
    val content = lazy storage.content.load();
    return {
        nextItemIndex: storage.nextItemIndex,
        collectionMetadata: content.collectionMetadata,
        adminAddress: storage.adminAddress,
    };
}

get fun get_nft_address_by_index(itemIndex: int): address {
    val storage = lazy NftCollectionV12Storage.load();
    return calcDeployedNftItemV12(
        itemIndex as uint64,
        contract.getAddress(),
        storage.nftItemCode,
    ).calculateAddress();
}

get fun royalty_params(): RoyaltyParams {
    val storage = lazy NftCollectionV12Storage.load();
    return storage.royaltyParams.load();
}

get fun get_nft_content(
    _itemIndex: int,
    individualNftContent: string,
): Cell<OffchainMetadataReply> {
    val storage = lazy NftCollectionV12Storage.load();
    val content = lazy storage.content.load();

    var builder = StringBuilder.create();
    builder.append(content.commonContent);
    builder.append(individualNftContent);
    return OffchainMetadataReply { string: builder.build() }.toCell();
}

get fun get_pending_nft_deployment(itemIndex: uint64): PendingNftDeploymentV12? {
    val storage = lazy NftCollectionV12Storage.load();
    val lookup = storage.pendingDeployments.get(itemIndex);
    if (!lookup.isFound) {
        return null;
    }
    return lookup.loadValue();
}
