import "@contracts/nft-v1.1/types"

struct (0x54474901) NftItemInitAtDeploymentV12 {
    queryId: uint64
    itemIndex: uint64
    ownerAddress: address
    content: string
}

struct (0x54474902) NftItemInitializedV12 {
    queryId: uint64
    itemIndex: uint64
}

struct (0x54474903) DeployNftV12 {
    queryId: uint64
    itemIndex: uint64
    attachTonAmount: coins
    ownerAddress: address
    content: string
}

struct (0x54474904) NftItemDeploymentConfirmedV12 {
    queryId: uint64
    itemIndex: uint64
    nftAddress: address
}

struct (0x54474905) NftItemDeploymentFailedV12 {
    queryId: uint64
    itemIndex: uint64
    exitCode: int32
}

struct (0x54474906) NftItemDeploymentAckV12 {
    queryId: uint64
    itemIndex: uint64
}

struct (0x54474907) RetryNftItemDeploymentNoticeV12 {
    queryId: uint64
    itemIndex: uint64
}

struct (0x54474908) RequestNftItemConfirmationV12 {
    queryId: uint64
    itemIndex: uint64
}
