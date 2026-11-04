import "@contracts/nft-v1.2/messages"

struct (0x54474101) CreateAuctionV1 {
    queryId: uint64
    itemIndex: uint64
    plate: string
    metadataContent: string
    startingBid: coins
    minimumBidStep: coins
    endTime: uint32
}

struct (0x54474102) PlaceBidV1 {
    queryId: uint64
    auctionId: uint64
    bidAmount: coins
}

struct (0x54474103) FinishAuctionV1 {
    queryId: uint64
    auctionId: uint64
}

struct (0x54474104) ClaimRefundV1 {
    queryId: uint64
}

struct (0x54474105) ClaimPayoutV1 {
    queryId: uint64
}

struct (0x54474106) SetPayoutAddressesV1 {
    queryId: uint64
    treasuryAddress: address?
    securityFundAddress: address?
}

struct (0x54474107) RefundTransferV1 {
    queryId: uint64
    auctionId: uint64
    beneficiary: address
    amount: coins
}

struct (0x54474108) PayoutTransferV1 {
    queryId: uint64
    auctionId: uint64
    beneficiary: address
    amount: coins
}

struct (0x54474109) MintFailureRefundV1 {
    queryId: uint64
    auctionId: uint64
    beneficiary: address
    amount: coins
}
