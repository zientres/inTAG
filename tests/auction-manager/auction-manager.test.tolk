import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/AuctionManager.gen"
import "@contracts/auction-manager/errors"
import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"
import "@contracts/nft-v1.2/messages"

fun setupAuctionManagerTest(): (AuctionManager, Treasury, Treasury, Treasury, Treasury) {
    val creator = testing.treasury("auction-creator");
    val collection = testing.treasury("nft-collection");
    val treasury = testing.treasury("treasury");
    val securityFund = testing.treasury("security-fund");
    val securityFundAddressForTest = securityFund.address;
    val manager = AuctionManager.fromStorage({
        ownerAddress: creator.address,
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
            plate: "А777АА77",
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

get fun `test auction manager: any wallet can create an auction and duplicate plate is rejected`() {
    val (manager, _, _, _, _) = setupAuctionManagerTest();
    val firstCreator = testing.treasury("permissionless-first-creator");
    val secondCreator = testing.treasury("permissionless-second-creator");
    val endTime = (blockchain.now() + 3600) as uint32;

    val create = manager.sendAny(
        firstCreator.address,
        CreateAuctionV1 {
            queryId: 2,
            plate: "В123ВВ77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(create).toHaveSuccessfulTx<CreateAuctionV1>({
        from: firstCreator.address,
        to: manager.address,
    });

    val duplicate = manager.sendAny(
        secondCreator.address,
        CreateAuctionV1 {
            queryId: 3,
            plate: "В123ВВ77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(duplicate).toHaveFailedTx<CreateAuctionV1>({
        from: secondCreator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.AuctionAlreadyExists,
    });
    expect(manager.getAuction(0)!.itemIndex).toEqual(0);
}

get fun `test auction manager: rejects a bid below the starting price`() {
    val (manager, creator, _, _, _) = setupAuctionManagerTest();
    manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 3,
            plate: "С555СС77",
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

get fun `test auction manager: rejects a bid below the minimum increment`() {
    val (manager, creator, _, _, _) = setupAuctionManagerTest();
    manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 5,
            plate: "Е555ЕЕ77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );

    val firstBidder = testing.treasury("minimum-step-first-bidder");
    val secondBidder = testing.treasury("minimum-step-second-bidder");
    val firstBid = manager.sendAny(
        firstBidder.address,
        PlaceBidV1 {
            queryId: 6,
            auctionId: 0,
            bidAmount: grams("1"),
        }.toCell(),
        { value: grams("1.2"), bounce: true },
    );
    expect(firstBid).toHaveSuccessfulTx<PlaceBidV1>({ to: manager.address });

    val secondBid = manager.sendAny(
        secondBidder.address,
        PlaceBidV1 {
            queryId: 7,
            auctionId: 0,
            bidAmount: grams("1.09"),
        }.toCell(),
        { value: grams("2.2"), bounce: true },
    );
    expect(secondBid).toHaveFailedTx<PlaceBidV1>({
        from: secondBidder.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.BidTooLow,
    });
    expect(manager.getAuction(0)!.highestBid).toEqual(grams("1"));
    expect(manager.getAuction(0)!.highestBidder!).toEqual(firstBidder.address);
}

get fun `test auction manager: rejects a bid at the exact deadline`() {
    val (manager, creator, _, _, _) = setupAuctionManagerTest();
    val deadline = (testing.getNow() + 10) as uint32;
    val create = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 8,
            plate: "К111КК77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: deadline,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(create).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });

    testing.setNow(deadline);
    val bidder = testing.treasury("deadline-bidder");
    val bid = manager.sendAny(
        bidder.address,
        PlaceBidV1 {
            queryId: 9,
            auctionId: 0,
            bidAmount: grams("1"),
        }.toCell(),
        { value: grams("1.2"), bounce: true },
    );
    expect(bid).toHaveFailedTx<PlaceBidV1>({
        from: bidder.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.BidAfterDeadline,
    });
    expect(manager.getAuction(0)!.highestBid).toEqual(0);
}

get fun `test auction manager: allows finishing at the exact deadline`() {
    val (manager, creator, collection, _, _) = setupAuctionManagerTest();
    val deadline = (testing.getNow() + 10) as uint32;
    val create = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 10,
            plate: "М222ММ77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: deadline,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(create).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });

    testing.setNow(deadline);
    val finish = manager.sendAny(
        testing.treasury("deadline-finisher").address,
        FinishAuctionV1 {
            queryId: 11,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.2"), bounce: true },
    );
    expect(finish).toHaveSuccessfulTx<FinishAuctionV1>({ to: manager.address });
    expect(finish).toHaveTx<SkipNftItemIndexV12>({
        from: manager.address,
        to: collection.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_SKIP);
    expect(manager.getPlateStatus(beginCell().storeStringTail("RU|А111АА77").endCell().hash())).toEqual(1);

    val ack = manager.sendAny(
        collection.address,
        NftItemIndexSkippedV12 {
            queryId: 1,
            itemIndex: 0,
        }.toCell(),
        { value: grams("0.03"), bounce: true },
    );
    expect(ack).toHaveSuccessfulTx<NftItemIndexSkippedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_NO_BIDS);
}

get fun `test auction manager: closes an empty auction by skipping its collection index`() {
    val creator = testing.treasury("empty-auction-creator");
    val collection = testing.treasury("empty-auction-collection");
    val securityFund = testing.treasury("empty-auction-security");
    val securityFundAddressForTest = securityFund.address;
    var plateToAuctionId: map<uint256, uint64> = [];
    plateToAuctionId.set(beginCell().storeStringTail("RU|А111АА77").endCell().hash(), 0);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "А111АА77",
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
        ownerAddress: creator.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId,
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: 0,
    });
    val deploy = manager.deploy(creator.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val finish = manager.sendAny(
        testing.treasury("finisher").address,
        FinishAuctionV1 {
            queryId: 101,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.2"), bounce: true },
    );
    expect(finish).toHaveSuccessfulTx<FinishAuctionV1>({
        to: manager.address,
    });
    expect(finish).toHaveTx<SkipNftItemIndexV12>({
        from: manager.address,
        to: collection.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_SKIP);

    val ack = manager.sendAny(
        collection.address,
        NftItemIndexSkippedV12 {
            queryId: 1,
            itemIndex: 0,
        }.toCell(),
        { value: grams("0.03"), bounce: true },
    );
    expect(ack).toHaveSuccessfulTx<NftItemIndexSkippedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_NO_BIDS);
    expect(manager.getPlateStatus(beginCell().storeStringTail("RU|А111АА77").endCell().hash())).toEqual(0);

    val relistUser = testing.treasury("empty-auction-relist-user");
    val relist = manager.sendAny(
        relistUser.address,
        CreateAuctionV1 {
            queryId: 102,
            plate: "А111АА77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(relist).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });
    expect(manager.getAuction(1)!.itemIndex).toEqual(1);
    expect(manager.getPlateStatus(beginCell().storeStringTail("RU|А111АА77").endCell().hash())).toEqual(1);
}

get fun `test auction manager: refunds the previous leader immediately`() {
    val (manager, creator, _, _, _) = setupAuctionManagerTest();
    val create = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 20,
            plate: "Н777НН77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(create).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });

    val firstBidder = testing.treasury("first-bidder");
    val secondBidder = testing.treasury("second-bidder");
    val firstBid = manager.sendAny(
        firstBidder.address,
        PlaceBidV1 {
            queryId: 21,
            auctionId: 0,
            bidAmount: grams("1"),
        }.toCell(),
        { value: grams("1.2"), bounce: true },
    );
    expect(firstBid).toHaveSuccessfulTx<PlaceBidV1>({ to: manager.address });

    val secondBid = manager.sendAny(
        secondBidder.address,
        PlaceBidV1 {
            queryId: 22,
            auctionId: 0,
            bidAmount: grams("1.1"),
        }.toCell(),
        { value: grams("1.3"), bounce: true },
    );
    expect(secondBid).toHaveSuccessfulTx<PlaceBidV1>({ to: manager.address });
    expect(secondBid).toHaveTx<RefundTransferV1>({
        from: manager.address,
        to: firstBidder.address,
    });
    expect(manager.getAuction(0)!.highestBid).toEqual(grams("1.1"));
    expect(manager.getAuction(0)!.highestBidder!).toEqual(secondBidder.address);
}

get fun `test auction manager: distributes the winning bid only after mint confirmation`() {
    val creator = testing.treasury("payout-creator");
    val collection = testing.treasury("payout-collection");
    val bidder = testing.treasury("payout-winner");
    val securityFund = testing.treasury("payout-security");
    val nftItem = testing.treasury("minted-nft-item");
    val securityFundAddressForTest = securityFund.address;
    var plateToAuctionId: map<uint256, uint64> = [];
    plateToAuctionId.set(beginCell().storeStringTail("RU|М222ММ77").endCell().hash(), 0);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "М222ММ77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("10"),
            highestBidder: bidder.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 77,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: creator.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 100,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId,
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("10"),
    });
    val deploy = manager.deploy(creator.address, { value: grams("10.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val confirmation = manager.sendAny(
        collection.address,
        NftItemDeploymentConfirmedV12 {
            queryId: 77,
            itemIndex: 0,
            nftAddress: nftItem.address,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(confirmation).toHaveSuccessfulTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
        to: manager.address,
    });
    expect(confirmation).toHaveTx<PayoutTransferV1>({
        from: manager.address,
        to: creator.address,
    });
    expect(confirmation).toHaveTx<PayoutTransferV1>({
        from: manager.address,
        to: securityFund.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);
    expect(manager.getTreasuryBalance()).toEqual(grams("3"));
    expect(manager.getPlateStatus(beginCell().storeStringTail("RU|М222ММ77").endCell().hash())).toEqual(2);

    val duplicate = manager.sendAny(
        testing.treasury("paid-plate-duplicate-user").address,
        CreateAuctionV1 {
            queryId: 79,
            plate: "М222ММ77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(duplicate).toHaveFailedTx<CreateAuctionV1>({
        to: manager.address,
        exitCode: AuctionManagerErrors.AuctionAlreadyExists,
    });
}

get fun `test auction manager: refunds winner if NFT deployment fails`() {
    val creator = testing.treasury("failed-mint-creator");
    val collection = testing.treasury("failed-mint-collection");
    val bidder = testing.treasury("failed-mint-winner");
    val securityFund = testing.treasury("failed-mint-security");
    val securityFundAddressForTest = securityFund.address;
    var plateToAuctionId: map<uint256, uint64> = [];
    plateToAuctionId.set(beginCell().storeStringTail("RU|С333СС77").endCell().hash(), 0);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "С333СС77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("4"),
            highestBidder: bidder.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 78,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: creator.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 100,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId,
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("4"),
    });
    val deploy = manager.deploy(creator.address, { value: grams("4.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val failure = manager.sendAny(
        collection.address,
        NftItemDeploymentFailedV12 {
            queryId: 78,
            itemIndex: 0,
            exitCode: 77,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(failure).toHaveSuccessfulTx<NftItemDeploymentFailedV12>({
        from: collection.address,
        to: manager.address,
    });
    expect(failure).toHaveTx<RefundTransferV1>({
        from: manager.address,
        to: bidder.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_MINT_FAILED);
    expect(manager.getPlateStatus(beginCell().storeStringTail("RU|С333СС77").endCell().hash())).toEqual(0);
}

get fun `test auction manager: bounced outbid refund becomes recoverable credit`() {
    val creator = testing.treasury("bounce-refund-creator");
    val collection = testing.treasury("bounce-refund-collection");
    val securityFund = testing.treasury("bounce-refund-security");
    val nextBidder = testing.treasury("bounce-refund-next-bidder");
    val unavailableBidder = randomAddress("unavailable-refund-recipient");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "BOUNCE 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
            highestBid: grams("1"),
            highestBidder: unavailableBidder,
            status: AUCTION_V1_ACTIVE,
            mintQueryId: 0,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: creator.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 100,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("1"),
    });
    val deploy = manager.deploy(creator.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val bid = manager.sendAny(
        nextBidder.address,
        PlaceBidV1 {
            queryId: 101,
            auctionId: 0,
            bidAmount: grams("1.1"),
        }.toCell(),
        { value: grams("1.3"), bounce: true },
    );
    expect(bid).toHaveSuccessfulTx<PlaceBidV1>({ to: manager.address });
    expect(manager.getAuction(0)!.highestBidder!).toEqual(nextBidder.address);
    expect(manager.getRefundCredit(unavailableBidder)).toEqual(grams("1"));
}

get fun `test auction manager: bounced creator payout becomes recoverable credit`() {
    val deployer = testing.treasury("bounce-payout-deployer");
    val collection = testing.treasury("bounce-payout-collection");
    val securityFund = testing.treasury("bounce-payout-security");
    val winner = testing.treasury("bounce-payout-winner");
    val unavailableCreator = randomAddress("unavailable-payout-recipient");
    val nftItem = testing.treasury("bounce-payout-nft-item");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "PAYOUT 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("10"),
            highestBidder: winner.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 88,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: unavailableCreator,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 100,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("10"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("10.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val confirmation = manager.sendAny(
        collection.address,
        NftItemDeploymentConfirmedV12 {
            queryId: 88,
            itemIndex: 0,
            nftAddress: nftItem.address,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(confirmation).toHaveSuccessfulTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
        to: manager.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);
    expect(manager.getPayoutCredit(unavailableCreator)).toEqual(grams("5"));
}

get fun `test auction manager: rejects refund claim without enough attached value`() {
    val deployer = testing.treasury("claim-refund-low-value-deployer");
    val beneficiary = testing.treasury("claim-refund-low-value-beneficiary");
    val collection = testing.treasury("claim-refund-low-value-collection");
    val securityFund = testing.treasury("claim-refund-low-value-security");
    val securityFundAddressForTest = securityFund.address;
    var refundCredits: map<address, coins> = [];
    refundCredits.set(beneficiary.address, grams("1"));
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 290,
        auctions: [],
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits,
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("1"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("1.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val claim = manager.sendAny(
        beneficiary.address,
        ClaimRefundV1 { queryId: 291 }.toCell(),
        { value: grams("0.001"), bounce: true },
    );
    expect(claim).toHaveFailedTx<ClaimRefundV1>({
        from: beneficiary.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InsufficientAttachedValue,
    });
    expect(manager.getRefundCredit(beneficiary.address)).toEqual(grams("1"));
}

get fun `test auction manager: beneficiary can claim bounced refund credit`() {
    val deployer = testing.treasury("claim-refund-deployer");
    val beneficiary = testing.treasury("claim-refund-beneficiary");
    val collection = testing.treasury("claim-refund-collection");
    val securityFund = testing.treasury("claim-refund-security");
    val securityFundAddressForTest = securityFund.address;
    var refundCredits: map<address, coins> = [];
    refundCredits.set(beneficiary.address, grams("1"));
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 300,
        auctions: [],
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits,
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("1"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("1.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val claim = manager.sendAny(
        beneficiary.address,
        ClaimRefundV1 { queryId: 301 }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(claim).toHaveSuccessfulTx<ClaimRefundV1>({ to: manager.address });
    expect(claim).toHaveTx<RefundTransferV1>({
        from: manager.address,
        to: beneficiary.address,
    });
    expect(manager.getRefundCredit(beneficiary.address)).toEqual(0);
}

get fun `test auction manager: rejects payout claim without enough attached value`() {
    val deployer = testing.treasury("claim-payout-low-value-deployer");
    val beneficiary = testing.treasury("claim-payout-low-value-beneficiary");
    val collection = testing.treasury("claim-payout-low-value-collection");
    val securityFund = testing.treasury("claim-payout-low-value-security");
    val securityFundAddressForTest = securityFund.address;
    var payoutCredits: map<address, coins> = [];
    payoutCredits.set(beneficiary.address, grams("5"));
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 390,
        auctions: [],
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits,
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val claim = manager.sendAny(
        beneficiary.address,
        ClaimPayoutV1 { queryId: 391 }.toCell(),
        { value: grams("0.001"), bounce: true },
    );
    expect(claim).toHaveFailedTx<ClaimPayoutV1>({
        from: beneficiary.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InsufficientAttachedValue,
    });
    expect(manager.getPayoutCredit(beneficiary.address)).toEqual(grams("5"));
}

get fun `test auction manager: beneficiary can claim bounced payout credit`() {
    val deployer = testing.treasury("claim-payout-deployer");
    val beneficiary = testing.treasury("claim-payout-beneficiary");
    val collection = testing.treasury("claim-payout-collection");
    val securityFund = testing.treasury("claim-payout-security");
    val securityFundAddressForTest = securityFund.address;
    var payoutCredits: map<address, coins> = [];
    payoutCredits.set(beneficiary.address, grams("5"));
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 400,
        auctions: [],
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits,
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val claim = manager.sendAny(
        beneficiary.address,
        ClaimPayoutV1 { queryId: 401 }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(claim).toHaveSuccessfulTx<ClaimPayoutV1>({ to: manager.address });
    expect(claim).toHaveTx<PayoutTransferV1>({
        from: manager.address,
        to: beneficiary.address,
    });
    expect(manager.getPayoutCredit(beneficiary.address)).toEqual(0);
}

get fun `test auction manager: payout addresses cannot change after first auction`() {
    val (manager, creator, _, _, securityFund) = setupAuctionManagerTest();
    val create = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 201,
            plate: "О333ОО77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(create).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });

    val change = manager.sendAny(
        creator.address,
        SetPayoutAddressesV1 {
            queryId: 202,
            securityFundAddress: securityFund.address,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(change).toHaveFailedTx<SetPayoutAddressesV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidPayoutConfiguration,
    });
}

get fun `test auction manager: bounced refund claim restores the credit`() {
    val deployer = testing.treasury("claim-bounce-refund-deployer");
    val unavailableBeneficiary = randomAddress("claim-bounce-refund-beneficiary");
    val collection = testing.treasury("claim-bounce-refund-collection");
    val securityFund = testing.treasury("claim-bounce-refund-security");
    val securityFundAddressForTest = securityFund.address;
    var refundCredits: map<address, coins> = [];
    refundCredits.set(unavailableBeneficiary, grams("1"));
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 500,
        auctions: [],
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits,
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("1"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("1.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val claim = manager.sendAny(
        unavailableBeneficiary,
        ClaimRefundV1 { queryId: 501 }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(claim).toHaveSuccessfulTx<ClaimRefundV1>({ to: manager.address });
    expect(manager.getRefundCredit(unavailableBeneficiary)).toEqual(grams("1"));
}

get fun `test auction manager: bounced payout claim restores the credit`() {
    val deployer = testing.treasury("claim-bounce-payout-deployer");
    val unavailableBeneficiary = randomAddress("claim-bounce-payout-beneficiary");
    val collection = testing.treasury("claim-bounce-payout-collection");
    val securityFund = testing.treasury("claim-bounce-payout-security");
    val securityFundAddressForTest = securityFund.address;
    var payoutCredits: map<address, coins> = [];
    payoutCredits.set(unavailableBeneficiary, grams("5"));
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 600,
        auctions: [],
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits,
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val claim = manager.sendAny(
        unavailableBeneficiary,
        ClaimPayoutV1 { queryId: 601 }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(claim).toHaveSuccessfulTx<ClaimPayoutV1>({ to: manager.address });
    expect(manager.getPayoutCredit(unavailableBeneficiary)).toEqual(grams("5"));
}

get fun `test auction manager: rejects NFT confirmation from an untrusted sender`() {
    val deployer = testing.treasury("forged-confirm-deployer");
    val collection = testing.treasury("forged-confirm-collection");
    val attacker = testing.treasury("forged-confirm-attacker");
    val winner = testing.treasury("forged-confirm-winner");
    val securityFund = testing.treasury("forged-confirm-security");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "FORGED 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("5"),
            highestBidder: winner.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 700,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 701,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val forged = manager.sendAny(
        attacker.address,
        NftItemDeploymentConfirmedV12 {
            queryId: 700,
            itemIndex: 0,
            nftAddress: testing.treasury("forged-nft-item").address,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(forged).toHaveFailedTx<NftItemDeploymentConfirmedV12>({
        from: attacker.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.NotFromCollection,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_MINT);
}

get fun `test auction manager: rejects NFT confirmation with an incorrect query id`() {
    val deployer = testing.treasury("wrong-query-deployer");
    val collection = testing.treasury("wrong-query-collection");
    val winner = testing.treasury("wrong-query-winner");
    val securityFund = testing.treasury("wrong-query-security");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "QUERY 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("5"),
            highestBidder: winner.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 710,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 711,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val wrongQuery = manager.sendAny(
        collection.address,
        NftItemDeploymentConfirmedV12 {
            queryId: 999,
            itemIndex: 0,
            nftAddress: testing.treasury("wrong-query-nft-item").address,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(wrongQuery).toHaveFailedTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidMintConfirmation,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_MINT);
}

get fun `test auction manager: rejects NFT failure from an untrusted sender`() {
    val deployer = testing.treasury("forged-failure-deployer");
    val collection = testing.treasury("forged-failure-collection");
    val attacker = testing.treasury("forged-failure-attacker");
    val winner = testing.treasury("forged-failure-winner");
    val securityFund = testing.treasury("forged-failure-security");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "FORGED FAIL 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("5"),
            highestBidder: winner.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 720,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 721,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val forged = manager.sendAny(
        attacker.address,
        NftItemDeploymentFailedV12 {
            queryId: 720,
            itemIndex: 0,
            exitCode: 77,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(forged).toHaveFailedTx<NftItemDeploymentFailedV12>({
        from: attacker.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.NotFromCollection,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_MINT);
    expect(manager.getRefundCredit(winner.address)).toEqual(0);
}

get fun `test auction manager: rejects NFT failure with an incorrect query id`() {
    val deployer = testing.treasury("wrong-failure-deployer");
    val collection = testing.treasury("wrong-failure-collection");
    val winner = testing.treasury("wrong-failure-winner");
    val securityFund = testing.treasury("wrong-failure-security");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "WRONG FAIL 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("5"),
            highestBidder: winner.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 730,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 731,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val wrongQuery = manager.sendAny(
        collection.address,
        NftItemDeploymentFailedV12 {
            queryId: 999,
            itemIndex: 0,
            exitCode: 77,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(wrongQuery).toHaveFailedTx<NftItemDeploymentFailedV12>({
        from: collection.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidMintConfirmation,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_MINT);
    expect(manager.getRefundCredit(winner.address)).toEqual(0);
}

get fun `test auction manager: duplicate mint confirmation does not pay out twice`() {
    val deployer = testing.treasury("duplicate-confirm-deployer");
    val collection = testing.treasury("duplicate-confirm-collection");
    val unavailableCreator = randomAddress("duplicate-confirm-creator");
    val winner = testing.treasury("duplicate-confirm-winner");
    val securityFund = testing.treasury("duplicate-confirm-security");
    val nftItem = testing.treasury("duplicate-confirm-nft-item");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "DUPLICATE 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("10"),
            highestBidder: winner.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 740,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: unavailableCreator,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 741,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("10"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("10.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val confirmation = NftItemDeploymentConfirmedV12 {
        queryId: 740,
        itemIndex: 0,
        nftAddress: nftItem.address,
    }.toCell();
    val first = manager.sendAny(
        collection.address,
        confirmation,
        { value: grams("0.05"), bounce: true },
    );
    expect(first).toHaveSuccessfulTx<NftItemDeploymentConfirmedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);
    expect(manager.getPayoutCredit(unavailableCreator)).toEqual(grams("5"));

    val replay = manager.sendAny(
        collection.address,
        confirmation,
        { value: grams("0.05"), bounce: true },
    );
    expect(replay).toHaveSuccessfulTx<NftItemDeploymentConfirmedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);
    expect(manager.getPayoutCredit(unavailableCreator)).toEqual(grams("5"));
}

get fun `test auction manager: duplicate mint failure does not refund twice`() {
    val deployer = testing.treasury("duplicate-failure-deployer");
    val collection = testing.treasury("duplicate-failure-collection");
    val unavailableWinner = randomAddress("duplicate-failure-winner");
    val securityFund = testing.treasury("duplicate-failure-security");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "DUPLICATE FAIL 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("5"),
            highestBidder: unavailableWinner,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 750,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 751,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("5"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val failure = NftItemDeploymentFailedV12 {
        queryId: 750,
        itemIndex: 0,
        exitCode: 77,
    }.toCell();
    val first = manager.sendAny(
        collection.address,
        failure,
        { value: grams("0.05"), bounce: true },
    );
    expect(first).toHaveSuccessfulTx<NftItemDeploymentFailedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_MINT_FAILED);
    expect(manager.getRefundCredit(unavailableWinner)).toEqual(grams("5"));

    val replay = manager.sendAny(
        collection.address,
        failure,
        { value: grams("0.05"), bounce: true },
    );
    expect(replay).toHaveSuccessfulTx<NftItemDeploymentFailedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_MINT_FAILED);
    expect(manager.getRefundCredit(unavailableWinner)).toEqual(grams("5"));
}

get fun `test auction manager: owner can withdraw part of treasury`() {
    val owner = testing.treasury("treasury-withdraw-owner");
    val collection = testing.treasury("treasury-withdraw-collection");
    val securityFundAddressForTest = testing.treasury("treasury-withdraw-security").address;
    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
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
        treasuryBalance: grams("5"),
        lockedFunds: 0,
    });
    val deploy = manager.deploy(owner.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val withdrawal = manager.sendAny(
        owner.address,
        WithdrawTreasuryV1 {
            queryId: 1,
            amount: grams("2"),
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(withdrawal).toHaveSuccessfulTx<WithdrawTreasuryV1>({ to: manager.address });
    expect(withdrawal).toHaveTx<TreasuryWithdrawalTransferV1>({
        from: manager.address,
        to: owner.address,
    });
    expect(manager.getTreasuryBalance()).toEqual(grams("3"));
}

get fun `test auction manager: owner can withdraw all remaining treasury in a later transaction`() {
    val owner = testing.treasury("treasury-full-withdraw-owner");
    val collection = testing.treasury("treasury-full-withdraw-collection");
    val securityFundAddressForTest = testing.treasury("treasury-full-withdraw-security").address;
    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
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
        treasuryBalance: grams("5"),
        lockedFunds: 0,
    });
    val deploy = manager.deploy(owner.address, { value: grams("5.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val first = manager.sendAny(
        owner.address,
        WithdrawTreasuryV1 {
            queryId: 1,
            amount: grams("2"),
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(first).toHaveSuccessfulTx<WithdrawTreasuryV1>({ to: manager.address });
    expect(manager.getTreasuryBalance()).toEqual(grams("3"));

    val second = manager.sendAny(
        owner.address,
        WithdrawTreasuryV1 {
            queryId: 2,
            amount: grams("3"),
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(second).toHaveSuccessfulTx<WithdrawTreasuryV1>({ to: manager.address });
    expect(second).toHaveTx<TreasuryWithdrawalTransferV1>({
        from: manager.address,
        to: owner.address,
    });
    expect(manager.getTreasuryBalance()).toEqual(0);
}

get fun `test auction manager: treasury withdrawal cannot use funds locked for bidders`() {
    val owner = testing.treasury("treasury-locked-owner");
    val collection = testing.treasury("treasury-locked-collection");
    val securityFundAddressForTest = testing.treasury("treasury-locked-security").address;
    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
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
        treasuryBalance: grams("2"),
        lockedFunds: grams("4"),
    });
    val deploy = manager.deploy(owner.address, { value: grams("4.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val withdrawal = manager.sendAny(
        owner.address,
        WithdrawTreasuryV1 {
            queryId: 1,
            amount: grams("2"),
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(withdrawal).toHaveFailedTx<WithdrawTreasuryV1>({
        from: owner.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InsufficientManagerBalance,
    });
    expect(manager.getTreasuryBalance()).toEqual(grams("2"));
}

get fun `test auction manager: treasury withdrawal is owner-only`() {
    val owner = testing.treasury("treasury-auth-owner");
    val attacker = testing.treasury("treasury-auth-attacker");
    val collection = testing.treasury("treasury-auth-collection");
    val securityFundAddressForTest = testing.treasury("treasury-auth-security").address;
    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
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
        treasuryBalance: grams("2"),
        lockedFunds: 0,
    });
    val deploy = manager.deploy(owner.address, { value: grams("2.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val withdrawal = manager.sendAny(
        attacker.address,
        WithdrawTreasuryV1 {
            queryId: 1,
            amount: grams("1"),
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(withdrawal).toHaveFailedTx<WithdrawTreasuryV1>({
        from: attacker.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.NotFromOwner,
    });
    expect(manager.getTreasuryBalance()).toEqual(grams("2"));
}

get fun `test auction manager: bounced treasury withdrawal restores treasury accounting`() {
    val deployer = testing.treasury("treasury-bounce-deployer");
    val unavailableOwner = randomAddress("treasury-bounce-unavailable-owner");
    val collection = testing.treasury("treasury-bounce-collection");
    val securityFundAddressForTest = testing.treasury("treasury-bounce-security").address;
    val manager = AuctionManager.fromStorage({
        ownerAddress: unavailableOwner,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
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
        treasuryBalance: grams("1"),
        lockedFunds: 0,
    });
    val deploy = manager.deploy(deployer.address, { value: grams("1.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val withdrawal = manager.sendAny(
        unavailableOwner,
        WithdrawTreasuryV1 {
            queryId: 1,
            amount: grams("1"),
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(withdrawal).toHaveSuccessfulTx<WithdrawTreasuryV1>({ to: manager.address });
    expect(manager.getTreasuryBalance()).toEqual(grams("1"));
}

get fun `test auction manager: bounced security fund payout becomes recoverable credit`() {
    val deployer = testing.treasury("bounce-security-deployer");
    val collection = testing.treasury("bounce-security-collection");
    val creator = testing.treasury("bounce-security-creator");
    val winner = testing.treasury("bounce-security-winner");
    val unavailableSecurityFund = randomAddress("unavailable-security-fund");
    val nftItem = testing.treasury("bounce-security-nft-item");
    val securityFundAddressForTest = unavailableSecurityFund;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "SECURITY PAYOUT 77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() - 1) as uint32,
            highestBid: grams("10"),
            highestBidder: winner.address,
            status: AUCTION_V1_WAITING_FOR_MINT,
            mintQueryId: 89,
        },
    );
    val manager = AuctionManager.fromStorage({
        ownerAddress: creator.address,
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 100,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: grams("10"),
    });
    val deploy = manager.deploy(deployer.address, { value: grams("10.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val confirmation = manager.sendAny(
        collection.address,
        NftItemDeploymentConfirmedV12 {
            queryId: 89,
            itemIndex: 0,
            nftAddress: nftItem.address,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(confirmation).toHaveSuccessfulTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
        to: manager.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);
    expect(manager.getPayoutCredit(unavailableSecurityFund)).toEqual(grams("2"));
}

get fun `test auction manager: waits for collection skip confirmation and handles duplicate ACK`() {
    val owner = testing.treasury("skip-ack-owner");
    val collection = testing.treasury("skip-ack-collection");
    val securityFund = testing.treasury("skip-ack-security");
    val securityFundAddressForTest = securityFund.address;
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "SKIP ACK 77",
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
        collectionAddress: collection.address,
        payoutConfigLocked: true,
        nextItemIndex: 1,
        nextMintItemIndex: 0,
        nextQueryId: 10,
        auctions,
        extra: AuctionManagerExtra {
            plateToAuctionId: [],
            securityFundAddress: securityFundAddressForTest,
        }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: 0,
    });
    val deploy = manager.deploy(owner.address, { value: grams("0.3"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });

    val finish = manager.sendAny(
        owner.address,
        FinishAuctionV1 {
            queryId: 1,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.2"), bounce: true },
    );
    expect(finish).toHaveSuccessfulTx<FinishAuctionV1>({ to: manager.address });
    expect(finish).toHaveTx<SkipNftItemIndexV12>({
        from: manager.address,
        to: collection.address,
        body: SkipNftItemIndexV12 {
            queryId: 10,
            itemIndex: 0,
        }.toCell(),
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_SKIP);

    val retry = manager.sendAny(
        owner.address,
        RetryMintNoticeV1 {
            queryId: 2,
            auctionId: 0,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    expect(retry).toHaveSuccessfulTx<RetryMintNoticeV1>({ to: manager.address });
    expect(retry).toHaveTx<SkipNftItemIndexV12>({
        from: manager.address,
        to: collection.address,
        body: SkipNftItemIndexV12 {
            queryId: 10,
            itemIndex: 0,
        }.toCell(),
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_WAITING_FOR_SKIP);

    val ack = manager.sendAny(
        collection.address,
        NftItemIndexSkippedV12 {
            queryId: 10,
            itemIndex: 0,
        }.toCell(),
        { value: grams("0.03"), bounce: true },
    );
    expect(ack).toHaveSuccessfulTx<NftItemIndexSkippedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_NO_BIDS);

    val replay = manager.sendAny(
        collection.address,
        NftItemIndexSkippedV12 {
            queryId: 10,
            itemIndex: 0,
        }.toCell(),
        { value: grams("0.03"), bounce: true },
    );
    expect(replay).toHaveSuccessfulTx<NftItemIndexSkippedV12>({ to: manager.address });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_NO_BIDS);
}
