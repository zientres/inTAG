const AUCTION_V1_ACTIVE = 0
const AUCTION_V1_WAITING_FOR_MINT = 1
const AUCTION_V1_CLOSED_NO_BIDS = 2
const AUCTION_V1_CLOSED_PAID = 3
const AUCTION_V1_CLOSED_MINT_FAILED = 4

const AUCTION_V1_MIN_BID_OVERHEAD = 100000000
const AUCTION_V1_MIN_CREATE_OVERHEAD = 30000000
const AUCTION_V1_MIN_FINISH_OVERHEAD = 150000000
const AUCTION_V1_COLLECTION_DEPLOY_VALUE = 100000000
const AUCTION_V1_ITEM_DEPLOY_VALUE = 20000000

struct AuctionV1 {
    itemIndex: uint64
    plate: string
    metadataContent: string
    startingBid: coins
    minimumBidStep: coins
    endTime: uint32
    highestBid: coins
    highestBidder: address?
    status: uint8
    mintQueryId: uint64
}

struct AuctionManagerStorage {
    ownerAddress: address
    creatorAddress: address
    collectionAddress: address
    treasuryAddress: address?
    securityFundAddress: address?
    nextAuctionId: uint64
    nextItemIndex: uint64
    nextQueryId: uint64
    auctions: map<uint64, AuctionV1>
    refundCredits: map<address, coins>
    payoutCredits: map<address, coins>
    processedBounces: map<uint64, bool>
}

fun AuctionManagerStorage.load(): AuctionManagerStorage {
    return AuctionManagerStorage.fromCell(contract.getData());
}

fun AuctionManagerStorage.save(self) {
    contract.setData(self.toCell());
}

fun isValidManagerAddress(addr: address): bool {
    return addr != address.fromWorkchainAndHash(0, 0);
}
