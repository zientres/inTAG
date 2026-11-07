import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@wrappers/AuctionManager.gen"
import "@wrappers/NftCollectionV12.gen"
import "@wrappers/NftItemV12.gen"

import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/messages"
import "@contracts/nft-v1.2/types"

get fun `test TagitalSpace auction: full auction, NFT mint confirmation and 30-50-20 distribution`() {
    val owner = testing.treasury("e2e-auction-owner");
    val bidder = testing.treasury("e2e-auction-winner");
    val securityFund = testing.treasury("e2e-auction-security");
    val finisher = testing.treasury("e2e-auction-finisher");

    // Deploy collection first; its admin is changed to AuctionManager after
    // the manager address has been derived from the collection address.
    val royaltyParams = RoyaltyParams {
        numerator: 2,
        denominator: 100,
        royaltyAddress: owner.address,
    };
    val collection = NftCollectionV12.fromStorage({
        adminAddress: owner.address,
        nextItemIndex: 0,
        content: CollectionContent {
            collectionMetadata: createEmptyCell(),
            commonContent: "ipfs://tagitalspace/",
        }.toCell(),
        nftItemCode: build("NftItemV12"),
        royaltyParams: royaltyParams.toCell(),
        pendingDeployments: [],
        lastSkippedItemIndex: 0,
        lastSkippedQueryId: 0,
    });
    val deployCollection = collection.deploy(
        owner.address,
        { value: grams("0.2"), bounce: false },
    );
    expect(deployCollection).toHaveSuccessfulDeploy({ to: collection.address });

    val securityFundAddressForTest: address? = null;
    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: collection.address,
        payoutConfigLocked: false,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions: [],
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: 0,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
    });
    val deployManager = manager.deploy(
        owner.address,
        { value: grams("0.2"), bounce: false },
    );
    expect(deployManager).toHaveSuccessfulDeploy({ to: manager.address });

    val changeAdmin = collection.sendChangeCollectionAdmin(
        owner.address,
        1,
        manager.address,
        { value: grams("0.05"), bounce: true },
    );
    expect(changeAdmin).toHaveSuccessfulTx<ChangeCollectionAdmin>({
        from: owner.address,
        to: collection.address,
    });
    expect(collection.getCollectionData().adminAddress).toEqual(manager.address);

    val configurePayout = manager.sendSetPayoutAddressesV1(
        owner.address,
        2,
        securityFund.address,
        { value: grams("0.05"), bounce: true },
    );
    expect(configurePayout).toHaveSuccessfulTx<SetPayoutAddressesV1>({
        from: owner.address,
        to: manager.address,
    });

    val endTime = (testing.getNow() + 10) as uint32;
    val auctionCreator = testing.treasury("permissionless-auction-creator");
    val createAuction = manager.sendAny(
        auctionCreator.address,
        CreateAuctionV1 {
            queryId: 3,
            plate: "А777АА77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(createAuction).toHaveSuccessfulTx<CreateAuctionV1>({
        from: auctionCreator.address,
        to: manager.address,
    });

    val bid = manager.sendAny(
        bidder.address,
        PlaceBidV1 {
            queryId: 4,
            auctionId: 0,
            bidAmount: grams("10"),
        }.toCell(),
        { value: grams("10.2"), bounce: true },
    );
    expect(bid).toHaveSuccessfulTx<PlaceBidV1>({
        from: bidder.address,
        to: manager.address,
    });
    expect(manager.getAuction(0)!.highestBid).toEqual(grams("10"));
    expect(manager.getAuction(0)!.highestBidder!).toEqual(bidder.address);

    testing.setNow(endTime);
    val finish = manager.sendAny(
        finisher.address,
        FinishAuctionV1 {
            queryId: 5,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.2"), bounce: true },
    );
    expect(finish).toHaveSuccessfulTx<FinishAuctionV1>({
        from: finisher.address,
        to: manager.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);

    val nftAddress = collection.getNftAddressByIndex(0);
    val nftItem = NftItemV12.fromAddress(nftAddress);
    val nftData = nftItem.getNftData();
    expect(nftData.isInitialized).toBeTrue();
    expect(nftData.itemIndex).toEqual(0);
    expect(nftData.ownerAddress!).toEqual(bidder.address);
    expect(nftData.collectionAddress).toEqual(collection.address);
    var metadataSlice = nftData.content!.beginParse();
    expect(metadataSlice.loadUint(8)).toEqual(0);
    val collectionMetadata = collection.getNftContent(0, nftData.content!);
    var collectionMetadataSlice = collectionMetadata.beginParse();
    expect(collectionMetadataSlice.loadUint(8)).toEqual(0);

    expect(finish).toHaveSuccessfulTx<DeployNftV12>({
        from: manager.address,
        to: collection.address,
    });
    expect(finish).toHaveSuccessfulDeploy({
        from: collection.address,
        to: nftAddress,
    });
    expect(finish).toHaveTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
        to: manager.address,
    });
    expect(finish).toHaveTx<PayoutTransferV1>({
        from: manager.address,
        to: owner.address,
    });
    expect(finish).toHaveTx<PayoutTransferV1>({
        from: manager.address,
        to: securityFund.address,
    });
    expect(finish).toHaveTx<NftItemDeploymentAckV12>({
        from: manager.address,
        to: collection.address,
    });

    expect(manager.getTreasuryBalance()).toEqual(grams("3"));
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);
    expect(collection.getPendingNftDeployment(0)).toBeNull();
}
