import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/AuctionManager.gen"
import "@contracts/auction-manager/errors"
import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"

fun setupFirstBidAuctionManagerTest(): (AuctionManager, Treasury, Treasury) {
    val owner = testing.treasury("first-bid-test-owner");
    val collection = testing.treasury("first-bid-test-collection");
    val securityFundAddressForTest = testing.treasury("first-bid-test-security").address;
    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: collection.address,
        payoutConfigLocked: false,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions: [],
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: 0,
    });
    val deploy = manager.deploy(owner.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });
    return (manager, owner, collection);
}

get fun `test auction manager: creates auction and records first bid in one transaction`() {
    val (manager, _, _) = setupFirstBidAuctionManagerTest();
    val firstBidder = testing.treasury("atomic-first-bidder");
    val firstBidAmount = grams("1");
    val endTime = (blockchain.now() + 3600) as uint32;

    val create = manager.sendAny(
        firstBidder.address,
        CreateAuctionWithFirstBidV1 {
            queryId: 1,
            plate: "А777АА77",
            startingBid: firstBidAmount,
            minimumBidStep: grams("0.1"),
            endTime,
        }.toCell(),
        { value: grams("1.1"), bounce: true },
    );

    expect(create).toHaveSuccessfulTx<CreateAuctionWithFirstBidV1>({
        from: firstBidder.address,
        to: manager.address,
    });
    val auction = manager.getAuction(0)!;
    expect(auction.itemIndex).toEqual(0);
    expect(auction.startingBid).toEqual(firstBidAmount);
    expect(auction.highestBid).toEqual(firstBidAmount);
    expect(auction.highestBidder!).toEqual(firstBidder.address);
    expect(auction.status).toEqual(AUCTION_V1_ACTIVE);
    expect(manager.getNextItemIndex()).toEqual(1);

    val nextBidder = testing.treasury("atomic-next-bidder");
    val nextBid = manager.sendAny(
        nextBidder.address,
        PlaceBidV1 {
            queryId: 2,
            auctionId: 0,
            bidAmount: grams("1.1"),
        }.toCell(),
        { value: grams("1.2"), bounce: true },
    );
    expect(nextBid).toHaveSuccessfulTx<PlaceBidV1>({ to: manager.address });
    expect(nextBid).toHaveTx<RefundTransferV1>({
        from: manager.address,
        to: firstBidder.address,
    });
    expect(manager.getAuction(0)!.highestBid).toEqual(grams("1.1"));
    expect(manager.getAuction(0)!.highestBidder!).toEqual(nextBidder.address);
}

get fun `test auction manager: rejects first bid when attached value does not cover bid and overhead`() {
    val (manager, _, _) = setupFirstBidAuctionManagerTest();
    val bidder = testing.treasury("atomic-underfunded-bidder");

    val create = manager.sendAny(
        bidder.address,
        CreateAuctionWithFirstBidV1 {
            queryId: 1,
            plate: "В123ВВ77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("1.05"), bounce: true },
    );

    expect(create).toHaveFailedTx<CreateAuctionWithFirstBidV1>({
        from: bidder.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InsufficientAttachedValue,
    });
    expect(manager.getNextItemIndex()).toEqual(0);
    expect(manager.getAuction(0) == null).toBeTrue();
}

get fun `test auction manager: rejects duplicate plate in atomic first bid transaction`() {
    val (manager, _, _) = setupFirstBidAuctionManagerTest();
    val firstBidder = testing.treasury("atomic-duplicate-first-bidder");
    val secondBidder = testing.treasury("atomic-duplicate-second-bidder");
    val endTime = (blockchain.now() + 3600) as uint32;

    val first = manager.sendAny(
        firstBidder.address,
        CreateAuctionWithFirstBidV1 {
            queryId: 1,
            plate: "С555СС77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime,
        }.toCell(),
        { value: grams("1.1"), bounce: true },
    );
    expect(first).toHaveSuccessfulTx<CreateAuctionWithFirstBidV1>({ to: manager.address });

    val duplicate = manager.sendAny(
        secondBidder.address,
        CreateAuctionWithFirstBidV1 {
            queryId: 2,
            plate: "С555СС77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime,
        }.toCell(),
        { value: grams("1.1"), bounce: true },
    );
    expect(duplicate).toHaveFailedTx<CreateAuctionWithFirstBidV1>({
        from: secondBidder.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.AuctionAlreadyExists,
    });
    expect(manager.getNextItemIndex()).toEqual(1);
    expect(manager.getAuction(0)!.highestBidder!).toEqual(firstBidder.address);
}
