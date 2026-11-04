import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/AuctionManager.gen"
import "@contracts/auction-manager/errors"
import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"

fun setupAuctionManagerTest(): (AuctionManager, Treasury, Treasury, Treasury, Treasury) {
    val creator = testing.treasury("auction-creator");
    val collection = testing.treasury("nft-collection");
    val treasury = testing.treasury("treasury");
    val securityFund = testing.treasury("security-fund");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    val manager = AuctionManager.fromStorage({
        ownerAddress: creator.address,
        collectionAddress: collection.address,
        payoutConfigLocked: false,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions: [],
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
    });
    val deploy = manager.deploy(creator.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });
    return (manager, creator, collection, treasury, securityFund);
}

get fun `test auction manager: creator can create sequential auction`() {
    val (manager, creator, _, _, _) = setupAuctionManagerTest();
    val endTime = (blockchain.now() + 3600) as uint32;
    val create = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 1,
            itemIndex: 0,
            plate: "A777AA 77",
            metadataContent: "0.json",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(create).toHaveSuccessfulTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
    });
    val auction = manager.getAuction(0);
    expect(auction!.itemIndex).toEqual(0);
    expect(auction!.startingBid).toEqual(grams("1"));
    expect(auction!.minimumBidStep).toEqual(grams("0.1"));
    expect(auction!.status).toEqual(AUCTION_V1_ACTIVE);
}

get fun `test auction manager: rejects auction creation from non-owner`() {
    val (manager, _, _, _, _) = setupAuctionManagerTest();
    val attacker = testing.treasury("unauthorized-creator");
    val create = manager.sendAny(
        attacker.address,
        CreateAuctionV1 {
            queryId: 2,
            itemIndex: 0,
            plate: "B123BB 77",
            metadataContent: "0.json",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(create).toHaveFailedTx<CreateAuctionV1>({
        from: attacker.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.NotFromOwner,
    });
}

get fun `test auction manager: rejects a bid below the starting price`() {
    val (manager, creator, _, _, _) = setupAuctionManagerTest();
    manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 3,
            itemIndex: 0,
            plate: "C555CC 77",
            metadataContent: "0.json",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );

    val bidder = testing.treasury("low-bidder");
    val bid = manager.sendAny(
        bidder.address,
        PlaceBidV1 {
            queryId: 4,
            auctionId: 0,
            bidAmount: grams("0.5"),
        }.toCell(),
        { value: grams("0.7"), bounce: true },
    );
    expect(bid).toHaveFailedTx<PlaceBidV1>({
        from: bidder.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.BidTooLow,
    });
}

get fun `test auction manager: closes an empty auction by skipping its collection index`() {
    val creator = testing.treasury("empty-auction-creator");
    val collection = testing.treasury("empty-auction-collection");
    val treasury = testing.treasury("empty-auction-treasury");
    val securityFund = testing.treasury("empty-auction-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(0, {
        itemIndex: 0,
        plate: "EMPTY 00",
        metadataContent: "empty.json",
        startingBid: grams("1"),
        minimumBidStep: grams("0.1"),
        endTime: (blockchain.now() - 1) as uint32,
        highestBid: 0,
        highestBidder: null,
        status: AUCTION_V1_ACTIVE,
        mintQueryId: 0,
    });
    val manager = AuctionManager.fromStorage({
        ownerAddress: creator.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions,
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
    });
    val deploy = manager.deploy(creator.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val finish = manager.sendAny(
        testing.treasury("finisher").address,
        FinishAuctionV1 { queryId: 101, auctionId: 0 }.toCell(),
        { value: grams("0.2"), bounce: true },
    );
    expect(finish).toHaveSuccessfulTx<FinishAuctionV1>({
        to: manager.address,
    });
    expect(finish).toHaveTx<SkipNftItemIndexV12>({
        from: manager.address,
        to: collection.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_NO_BIDS);
}
