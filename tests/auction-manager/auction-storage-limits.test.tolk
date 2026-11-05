import "@stdlib/strings"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/AuctionManager.gen"
import "@contracts/auction-manager/errors"
import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"

fun setupAuctionStorageLimitsTest(): (AuctionManager, Treasury) {
    val creator = testing.treasury("storage-limit-creator");
    val collection = testing.treasury("storage-limit-collection");
    val treasury = testing.treasury("storage-limit-treasury");
    val securityFund = testing.treasury("storage-limit-security");
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
    return (manager, creator);
}

fun createAuctionWithContent(
    manager: AuctionManager,
    creator: Treasury,
    plate: string,
    metadataContent: string,
): SendResultList {
    return manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 1,
            itemIndex: 0,
            plate,
            metadataContent,
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
}

get fun `test auction manager: accepts maximum configured content lengths`() {
    val (manager, creator) = setupAuctionStorageLimitsTest();
    val result = createAuctionWithContent(
        manager,
        creator,
        "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP",
        "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm",
    );

    expect(result).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });
    expect(manager.getAuction(0)!.plate.calculateLength()).toEqual(64);
    expect(manager.getAuction(0)!.metadataContent.calculateLength()).toEqual(256);
}

get fun `test auction manager: rejects plate longer than 64 bytes`() {
    val (manager, creator) = setupAuctionStorageLimitsTest();
    val result = createAuctionWithContent(
        manager,
        creator,
        "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP",
        "0.json",
    );

    expect(result).toHaveFailedTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidAuctionParameters,
    });
    expect(manager.getAuction(0)).toEqual(null);
}

get fun `test auction manager: rejects metadata path longer than 256 bytes`() {
    val (manager, creator) = setupAuctionStorageLimitsTest();
    val result = createAuctionWithContent(
        manager,
        creator,
        "A777AA 77",
        "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm",
    );

    expect(result).toHaveFailedTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidAuctionParameters,
    });
    expect(manager.getAuction(0)).toEqual(null);
}

get fun `test auction manager: rejects empty plate`() {
    val (manager, creator) = setupAuctionStorageLimitsTest();
    val result = createAuctionWithContent(manager, creator, "", "0.json");

    expect(result).toHaveFailedTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidAuctionParameters,
    });
    expect(manager.getAuction(0)).toEqual(null);
}

get fun `test auction manager: rejects empty metadata path`() {
    val (manager, creator) = setupAuctionStorageLimitsTest();
    val result = createAuctionWithContent(manager, creator, "A777AA 77", "");

    expect(result).toHaveFailedTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidAuctionParameters,
    });
    expect(manager.getAuction(0)).toEqual(null);
}
