# Auction Manager v1

Auction Manager is the only contract allowed to mint through the compatible NFT Collection v1.2. It accepts bids, refunds outbid leaders, finishes auctions, requests verified NFT deployment, and distributes the winning bid only after the collection confirms the NFT item.

## Lifecycle

1. The owner configures one Development/Security fund address before the first auction. The auction treasury remains inside Auction Manager; no separate treasury wallet is required.
2. The owner creates auctions with sequential collection item indexes, a starting bid, a minimum bid step, end time, plate text, and a published metadata filename.
3. Bidders send `PlaceBidV1` with the exact bid amount in the body and enough attached TON for the bid plus the contract's fee reserve.
4. When a higher bid is accepted, the previous leader is refunded immediately. If that transfer bounces, the full amount becomes a claimable refund credit.
5. Anyone can finish an ended auction. An auction with no bids consumes its reserved collection index using `SkipNftItemIndexV12`; an auction with a winner asks Collection v1.2 to deploy the NFT to that winner.
6. After `NftItemDeploymentConfirmedV12` from the configured collection, the manager retains 30% in its internal treasury accounting, pays 50% to the owner wallet, and pays 20% to Development/Security.
7. If NFT deployment fails, the winner's bid is refunded. Bounced refund or payout transfers become claimable credits.

## Recovery

- `RetryMintNoticeV1` forwards a retry request to the collection if the deployment or confirmation notice is still pending.
- `ClaimRefundV1` claims a bounced outbid or mint-failure refund.
- `ClaimPayoutV1` claims a bounced payout.
- Query IDs are unique for outgoing transfers. Auction status checks prevent duplicate finishing and duplicate payout.

## Configuration and security

- Owner and creator are the same wallet in this version.
- The Development/Security address must be non-zero and distinct from the owner. The 30% treasury share remains in the Auction Manager contract.
- The Development/Security address is locked when the first auction is created.
- `get_treasury_balance` returns the amount recorded as treasury funds. The owner can send `WithdrawTreasuryV1` to withdraw any positive amount, including partial withdrawals, to the configured owner wallet.
- Withdrawals are limited by the recorded treasury amount and by the contract's actual balance after protecting locked bids, refund credits, payout credits, and a 0.2 TON operational reserve. A bounced withdrawal restores the treasury accounting.
- `lockedFunds` is an aggregate liability counter; it is updated when bids, refunds, and payouts enter or leave escrow. No transaction history is stored on-chain; use a TON explorer for history.
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
