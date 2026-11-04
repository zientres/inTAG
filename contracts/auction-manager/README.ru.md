# Auction Manager v1

Auction Manager is the only contract allowed to mint through the compatible NFT Collection v1.2. It accepts bids, refunds outbid leaders, finishes auctions, requests verified NFT deployment, and distributes the winning bid only after the collection confirms the NFT item.

## Lifecycle

1. The owner configures distinct Treasury and Development/Security addresses before the first auction.
2. The owner creates auctions with sequential collection item indexes, a starting bid, a minimum bid step, end time, plate text, and a published metadata filename.
3. Bidders send `PlaceBidV1` with the exact bid amount in the body and enough attached TON for the bid plus the contract's fee reserve.
4. When a higher bid is accepted, the previous leader is refunded immediately. If that transfer bounces, the full amount becomes a claimable refund credit.
5. Anyone can finish an ended auction. An auction with no bids consumes its reserved collection index using `SkipNftItemIndexV12`; an auction with a winner asks Collection v1.2 to deploy the NFT to that winner.
6. The manager pays 50% to the creator, 30% to Treasury, and 20% to Development/Security only after `NftItemDeploymentConfirmedV12` from the configured collection.
7. If NFT deployment fails, the winner's bid is refunded. Bounced refund or payout transfers become claimable credits.

## Recovery

- `RetryMintNoticeV1` forwards a retry request to the collection if the deployment or confirmation notice is still pending.
- `ClaimRefundV1` claims a bounced outbid or mint-failure refund.
- `ClaimPayoutV1` claims a bounced payout.
- Query IDs are unique for outgoing transfers. Auction status checks prevent duplicate finishing and duplicate payout.

## Configuration and security

- Owner and creator are the same wallet in this version.
- Treasury and Development/Security addresses must be non-zero and distinct from each other and the creator.
- Payout addresses are locked when the first auction is created.
- Collection item indexes are consumed sequentially. A no-bid auction skips its index; a failed NFT deployment also consumes its index, so an index is never reused.
- The manager must be set as admin of the v1.2 collection before auctions are enabled.
- The deployment and configuration scripts explicitly target TON Testnet. Do not use them on Mainnet.
- This implementation is not audited. Do not transfer collection admin or deploy with real funds until the complete test suite and an independent security review are finished.

## Commands

```bash
acton test tests/auction-manager
acton script scripts/deployAuctionManager.tolk --net testnet --tonconnect
acton script scripts/configureAuctionManager.tolk --net testnet --tonconnect
acton script scripts/transferCollectionAdminToAuctionManager.tolk --net testnet --tonconnect
```
