import "@contracts/nft-v1.1/types"

const NFT_V12_DEPLOYMENT_WAITING_FOR_ITEM = 0
const NFT_V12_DEPLOYMENT_READY_FOR_MANAGER = 1
const NFT_V12_DEPLOYMENT_FAILED = 2

struct PendingNftDeploymentV12 {
    queryId: uint64
    managerAddress: address
    itemAddress: address
    status: uint8
    exitCode: int32
}

struct NftCollectionV12Storage {
    adminAddress: address
    nextItemIndex: uint64
    content: Cell<CollectionContent>
    nftItemCode: cell
    royaltyParams: Cell<RoyaltyParams>
    pendingDeployments: map<uint64, PendingNftDeploymentV12>
}

fun NftCollectionV12Storage.load(): NftCollectionV12Storage {
    return NftCollectionV12Storage.fromCell(contract.getData());
}

fun NftCollectionV12Storage.save(self) {
    contract.setData(self.toCell());
}

fun calcDeployedNftItemV12(
    itemIndex: uint64,
    collectionAddress: address,
    nftItemCode: cell,
): AutoDeployAddress {
    val emptyNftItemStorage: NftItemStorageNotInitialized = {
        itemIndex,
        collectionAddress,
    };
    return { stateInit: { code: nftItemCode, data: emptyNftItemStorage.toCell() } };
}
