import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/AuctionManager.gen"
import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"

get fun `test auction manager: bounced NFT deployment reopens auction for retry`() {
    val owner = testing.treasury("bounce-deploy-owner");
    val bidder = testing.treasury("bounce-deploy-bidder");
    val finisher = testing.treasury("bounce-deploy-finisher");
    val unavailableCollection = randomAddress("bounce-deploy-unavailable-collection");

    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "BOUNCE DEPLOY",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("1"),
            highestBidder: bidder.address,
            status: AUCTION_V1_ACTIVE,
            mintQueryId: 0,
        },
    );

    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: unavailableCollection,
        payoutConfigLocked: false,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: null,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("1"),
    });
    val deploy = manager.deploy(owner.address, { value: grams("1.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val finish = manager.sendAny(
        finisher.address,
        FinishAuctionV1 {
            queryId: 1,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.2"), bounce: true },
    );
    expect(finish).toHaveSuccessfulTx<FinishAuctionV1>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_ACTIVE);
    expect(manager.getAuction(0)!.mintQueryId).toEqual(0);
}

get fun `test auction manager: bounced empty-index skip restores auction sequence`() {
    val owner = testing.treasury("bounce-skip-owner");
    val finisher = testing.treasury("bounce-skip-finisher");
    val unavailableCollection = randomAddress("bounce-skip-unavailable-collection");

    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "BOUNCE SKIP",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: 0,
            highestBidder: null,
            status: AUCTION_V1_ACTIVE,
            mintQueryId: 0,
        },
    );

    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: unavailableCollection,
        payoutConfigLocked: false,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: null,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: 0,
    });
    val deploy = manager.deploy(owner.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val finish = manager.sendAny(
        finisher.address,
        FinishAuctionV1 {
            queryId: 2,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.2"), bounce: true },
    );
    expect(finish).toHaveSuccessfulTx<FinishAuctionV1>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_SKIP);
    expect(manager.getAuction(0)!.mintQueryId).toEqual(1);

    val retry = manager.sendAny(
        finisher.address,
        RetryMintNoticeV1 {
            queryId: 3,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(retry).toHaveSuccessfulTx<RetryMintNoticeV1>({ to: manager.address });
    expect(retry).toHaveTx<SkipNftItemIndexV12>({
        from: manager.address,
        to: unavailableCollection,
        body: SkipNftItemIndexV12 {
            queryId: 1,
            itemIndex: 0,
        }.toCell(),
    });
}
