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
    auctions.set(
        0,
        {
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_NO_BIDS);
}

get fun `test auction manager: refunds the previous leader immediately`() {
    val (manager, creator, _, _, _) = setupAuctionManagerTest();
    val create = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 20,
            itemIndex: 0,
            plate: "B777BB 77",
            metadataContent: "1.json",
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
    val treasury = testing.treasury("payout-treasury");
    val securityFund = testing.treasury("payout-security");
    val nftItem = testing.treasury("minted-nft-item");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "WINNER 77",
            metadataContent: "winner.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
        to: treasury.address,
    });
    expect(confirmation).toHaveTx<PayoutTransferV1>({
        from: manager.address,
        to: securityFund.address,
    });
    expect(manager.getAuction(0)!.status).toEqual(AUCTION_V1_CLOSED_PAID);
}

get fun `test auction manager: refunds winner if NFT deployment fails`() {
    val creator = testing.treasury("failed-mint-creator");
    val collection = testing.treasury("failed-mint-collection");
    val bidder = testing.treasury("failed-mint-winner");
    val treasury = testing.treasury("failed-mint-treasury");
    val securityFund = testing.treasury("failed-mint-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "FAILED 77",
            metadataContent: "failed.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
}

get fun `test auction manager: bounced outbid refund becomes recoverable credit`() {
    val creator = testing.treasury("bounce-refund-creator");
    val collection = testing.treasury("bounce-refund-collection");
    val treasury = testing.treasury("bounce-refund-treasury");
    val securityFund = testing.treasury("bounce-refund-security");
    val nextBidder = testing.treasury("bounce-refund-next-bidder");
    val unavailableBidder = randomAddress("unavailable-refund-recipient");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "BOUNCE 77",
            metadataContent: "bounce.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("bounce-payout-treasury");
    val securityFund = testing.treasury("bounce-payout-security");
    val winner = testing.treasury("bounce-payout-winner");
    val unavailableCreator = randomAddress("unavailable-payout-recipient");
    val nftItem = testing.treasury("bounce-payout-nft-item");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "PAYOUT 77",
            metadataContent: "payout.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("claim-refund-low-value-treasury");
    val securityFund = testing.treasury("claim-refund-low-value-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
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
        refundCredits,
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("claim-refund-treasury");
    val securityFund = testing.treasury("claim-refund-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
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
        refundCredits,
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("claim-payout-low-value-treasury");
    val securityFund = testing.treasury("claim-payout-low-value-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
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
        refundCredits: [],
        payoutCredits,
        payoutAddresses,
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
    val treasury = testing.treasury("claim-payout-treasury");
    val securityFund = testing.treasury("claim-payout-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
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
        refundCredits: [],
        payoutCredits,
        payoutAddresses,
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
    val (manager, creator, _, treasury, securityFund) = setupAuctionManagerTest();
    val create = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 201,
            itemIndex: 0,
            plate: "LOCK 77",
            metadataContent: "lock.json",
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
            treasuryAddress: treasury.address,
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
    val treasury = testing.treasury("claim-bounce-refund-treasury");
    val securityFund = testing.treasury("claim-bounce-refund-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
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
        refundCredits,
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("claim-bounce-payout-treasury");
    val securityFund = testing.treasury("claim-bounce-payout-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
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
        refundCredits: [],
        payoutCredits,
        payoutAddresses,
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
    val treasury = testing.treasury("forged-confirm-treasury");
    val securityFund = testing.treasury("forged-confirm-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "FORGED 77",
            metadataContent: "forged.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("wrong-query-treasury");
    val securityFund = testing.treasury("wrong-query-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "QUERY 77",
            metadataContent: "query.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("forged-failure-treasury");
    val securityFund = testing.treasury("forged-failure-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "FORGED FAIL 77",
            metadataContent: "forged-failure.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("wrong-failure-treasury");
    val securityFund = testing.treasury("wrong-failure-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "WRONG FAIL 77",
            metadataContent: "wrong-failure.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("duplicate-confirm-treasury");
    val securityFund = testing.treasury("duplicate-confirm-security");
    val nftItem = testing.treasury("duplicate-confirm-nft-item");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "DUPLICATE 77",
            metadataContent: "duplicate.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
    val treasury = testing.treasury("duplicate-failure-treasury");
    val securityFund = testing.treasury("duplicate-failure-security");
    var payoutAddresses: map<uint8, address> = [];
    payoutAddresses.set(0, treasury.address);
    payoutAddresses.set(1, securityFund.address);
    var auctions: map<uint64, AuctionV1> = [];
    auctions.set(
        0,
        {
            itemIndex: 0,
            plate: "DUPLICATE FAIL 77",
            metadataContent: "duplicate-failure.json",
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
        refundCredits: [],
        payoutCredits: [],
        payoutAddresses,
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
