import "@stdlib/strings"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/AuctionManager.gen"
import "@contracts/auction-manager/errors"
import "@contracts/auction-manager/messages"
import "@contracts/auction-manager/types"

fun setupAuctionRegistryTest(): (AuctionManager, Treasury, Treasury) {
    val owner = testing.treasury("registry-owner");
    val creator = testing.treasury("registry-user");
    val collection = testing.treasury("registry-collection");
    val securityFund = testing.treasury("registry-security");
    val manager = AuctionManager.fromStorage({
        ownerAddress: owner.address,
        collectionAddress: collection.address,
        payoutConfigLocked: false,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions: [],
        plateRegistry: AuctionManagerPlateRegistry { plateToAuctionId: [] }.toCell(),
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: 0,
        securityFundAddress: securityFund.address,
    });
    val deploy = manager.deploy(owner.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: manager.address });
    return (manager, creator, owner);
}

fun createRegistryAuction(
    manager: AuctionManager,
    creator: Treasury,
    plate: string,
    queryId: uint64,
): SendResultList {
    return manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId,
            plate,
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 3600) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
}

get fun `test auction manager: accepts a valid Russian plate format`() {
    val (manager, creator, _) = setupAuctionRegistryTest();
    val plate = "А777АА77";
    val result = createRegistryAuction(manager, creator, plate, 1);

    expect(result).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });
    expect(manager.getAuction(0)!.plate.calculateLength()).toEqual(11);
}

get fun `test auction manager: accepts a three-digit region code`() {
    val (manager, creator, _) = setupAuctionRegistryTest();
    val plate = "А777АА777";
    val result = createRegistryAuction(manager, creator, plate, 8);

    expect(result).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });
    expect(manager.getAuction(0)!.plate.calculateLength()).toEqual(12);
}

get fun `test auction manager: rejects non-Russian plate format`() {
    val (manager, creator, _) = setupAuctionRegistryTest();
    val plate = "A777AA77";
    val result = createRegistryAuction(manager, creator, plate, 2);

    expect(result).toHaveFailedTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidAuctionParameters,
    });
    expect(manager.getAuction(0)).toEqual(null);
}

get fun `test auction manager: rejects empty plate`() {
    val (manager, creator, _) = setupAuctionRegistryTest();
    val result = createRegistryAuction(manager, creator, "", 3);

    expect(result).toHaveFailedTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidAuctionParameters,
    });
    expect(manager.getAuction(0)).toEqual(null);
}


get fun `test auction manager: rejects auctions longer than two hours`() {
    val (manager, creator, _) = setupAuctionRegistryTest();
    val result = manager.sendAny(
        creator.address,
        CreateAuctionV1 {
            queryId: 7,
            plate: "С555СС77",
            startingBid: grams("1"),
            minimumBidStep: grams("0.1"),
            endTime: (blockchain.now() + 7201) as uint32,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );

    expect(result).toHaveFailedTx<CreateAuctionV1>({
        from: creator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.InvalidAuctionParameters,
    });
    expect(manager.getAuction(0)).toEqual(null);
}

get fun `test auction manager: any wallet can create an auction and registry reports it`() {
    val (manager, creator, _) = setupAuctionRegistryTest();
    val plate = "А777АА77";
    val result = createRegistryAuction(manager, creator, plate, 4);

    expect(result).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });
    val plateHash = StringBuilder.create().append("RU|").append(plate).build().hash();
    val status = manager.getPlateStatus(plateHash);
    expect(status).toEqual(1);
}

get fun `test auction manager: rejects duplicate plate auctions from different wallets`() {
    val (manager, creator, _) = setupAuctionRegistryTest();
    val secondCreator = testing.treasury("registry-second-user");
    val plate = "В123ВВ77";
    val first = createRegistryAuction(manager, creator, plate, 5);
    expect(first).toHaveSuccessfulTx<CreateAuctionV1>({ to: manager.address });

    val duplicate = createRegistryAuction(manager, secondCreator, plate, 6);
    expect(duplicate).toHaveFailedTx<CreateAuctionV1>({
        from: secondCreator.address,
        to: manager.address,
        exitCode: AuctionManagerErrors.AuctionAlreadyExists,
    });
}
