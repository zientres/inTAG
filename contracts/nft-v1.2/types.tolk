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
    lastSkippedItemIndex: uint64
    lastSkippedQueryId: uint64
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
    val emptyNftItemStorage: NftItemV12StorageNotInitialized = { itemIndex, collectionAddress };
    return { stateInit: { code: nftItemCode, data: emptyNftItemStorage.toCell() } };
}

struct NftItemV12Storage {
    itemIndex: uint64
    collectionAddress: address
    ownerAddress: address
    content: cell
    initQueryId: uint64
}

struct NftDataReplyV12 {
    isInitialized: bool
    itemIndex: int
    collectionAddress: address
    ownerAddress: address? = null
    content: cell? = null
}

struct NftItemV12StorageNotInitialized {
    itemIndex: uint64
    collectionAddress: address
}

struct NftItemV12StorageLoader {
    itemIndex: uint64
    collectionAddress: address
    private rest: RemainingBitsAndRefs
}

fun NftItemV12StorageLoader.isNotInitialized(self): bool {
    return self.rest.isEmpty();
}

fun NftItemV12StorageLoader.endLoading(mutate self): NftItemV12Storage {
    return {
        itemIndex: self.itemIndex,
        collectionAddress: self.collectionAddress,
        ownerAddress: self.rest.loadAny(),
        content: self.rest.loadAny(),
        initQueryId: self.rest.loadAny(),
    };
}

fun NftItemV12Storage.startLoading(): NftItemV12StorageLoader {
    return NftItemV12StorageLoader.fromCell(contract.getData());
}

fun NftItemV12Storage.save(self) {
    contract.setData(self.toCell());
}
