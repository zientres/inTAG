import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"
import "@wrappers/NftCollectionV12.gen"
import "@wrappers/NftItemV12.gen"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/errors"
import "@contracts/nft-v1.2/messages"
import "@contracts/nft-v1.2/types"

fun setupNftCollectionV12Test(): (NftCollectionV12, Treasury, Treasury) {
    val manager = testing.treasury("auction-manager");
    val owner = testing.treasury("nft-owner");
    val royaltyParams = RoyaltyParams {
        numerator: 2,
        denominator: 100,
        royaltyAddress: manager.address,
    };

    val collection = NftCollectionV12.fromStorage({
        adminAddress: manager.address,
        nextItemIndex: 0,
        content: CollectionContent {
            collectionMetadata: createEmptyCell(),
            commonContent: "ipfs://tagitalspace/",
        }.toCell(),
        nftItemCode: build("NftItemV12"),
        royaltyParams: royaltyParams.toCell(),
        pendingDeployments: [],
    });

    val deploy = collection.deploy(manager.address, { value: grams("0.2"), bounce: false });
    expect(deploy).toHaveSuccessfulDeploy({ to: collection.address });
    return (collection, manager, owner);
}

get fun `test nft v1.2: confirms item initialization before manager notification`() {
    val (collection, manager, owner) = setupNftCollectionV12Test();
    val queryId = 12001;
    val itemIndex = 0;
    val content = "0.json";

    val deploy = collection.sendDeployNftV12(
        manager.address,
        queryId,
        itemIndex,
        grams("0.02"),
        owner.address,
        content,
        { value: grams("0.1"), bounce: true },
    );

    expect(deploy).toHaveSuccessfulTx<DeployNftV12>({
        from: manager.address,
        to: collection.address,
    });

    val nftAddress = collection.getNftAddressByIndex(itemIndex);
    expect(deploy).toHaveSuccessfulDeploy({
        from: collection.address,
        to: nftAddress,
    });

    val nft = NftItemV12.fromAddress(nftAddress);
    val nftData = nft.getNftData();
    expect(nftData.isInitialized).toBeTrue();
    expect(nftData.itemIndex).toEqual(itemIndex);
    expect(nftData.ownerAddress!).toEqual(owner.address);
    expect(nftData.collectionAddress).toEqual(collection.address);

    expect(deploy).toHaveTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
        to: manager.address,
        body: NftItemDeploymentConfirmedV12 { queryId, itemIndex, nftAddress }.toCell(),
    });

    val pending = collection.getPendingNftDeployment(itemIndex as uint64);
    expect(pending!.queryId).toEqual(queryId);
    expect(pending!.managerAddress).toEqual(manager.address);
    expect(pending!.itemAddress).toEqual(nftAddress);
    expect(pending!.status).toEqual(NFT_V12_DEPLOYMENT_READY_FOR_MANAGER);

    val ack = collection.sendNftItemDeploymentAckV12(
        manager.address,
        queryId,
        itemIndex,
        { value: grams("0.03"), bounce: true },
    );
    expect(ack).toHaveSuccessfulTx<NftItemDeploymentAckV12>({
        from: manager.address,
        to: collection.address,
    });
    expect(collection.getPendingNftDeployment(itemIndex as uint64)).toBeNull();
}

get fun `test nft v1.2: allows manager to retry an unacknowledged notice`() {
    val (collection, manager, owner) = setupNftCollectionV12Test();
    val queryId = 12002;
    val itemIndex = 0;

    collection.sendDeployNftV12(
        manager.address,
        queryId,
        itemIndex,
        grams("0.02"),
        owner.address,
        "retry.json",
        { value: grams("0.1"), bounce: true },
    );

    val retry = collection.sendRetryNftItemDeploymentNoticeV12(
        manager.address,
        queryId,
        itemIndex,
        { value: grams("0.03"), bounce: true },
    );
    expect(retry).toHaveSuccessfulTx<RetryNftItemDeploymentNoticeV12>({
        from: manager.address,
        to: collection.address,
    });
    expect(retry).toHaveTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
        to: manager.address,
    });
}

get fun `test nft v1.2: rejects deployment from non-admin`() {
    val (collection, _, owner) = setupNftCollectionV12Test();
    val attacker = testing.treasury("unauthorized-minter");

    val result = collection.sendDeployNftV12(
        attacker.address,
        12003,
        0,
        grams("0.02"),
        owner.address,
        "unauthorized.json",
        { value: grams("0.1"), bounce: true },
    );

    expect(result).toHaveFailedTx<DeployNftV12>({
        from: attacker.address,
        to: collection.address,
        exitCode: NftV12Errors.NotFromAdmin,
    });
}

get fun `test nft v1.2: rejects forged item initialization callback`() {
    val (collection, _, _) = setupNftCollectionV12Test();
    val attacker = testing.treasury("forged-nft-item");
    val forged = NftItemInitializedV12 {
        queryId: 13001,
        itemIndex: 0,
    }.toCell();

    val result = collection.sendAny(
        attacker.address,
        forged,
        { value: grams("0.03"), bounce: true },
    );

    expect(result).toHaveFailedTx<NftItemInitializedV12>({
        from: attacker.address,
        to: collection.address,
        exitCode: NftV12Errors.NotFromExpectedNftItem,
    });
}

get fun `test nft v1.2: only manager can acknowledge deployment`() {
    val (collection, manager, owner) = setupNftCollectionV12Test();
    val attacker = testing.treasury("fake-manager");
    val queryId = 13002;
    val itemIndex = 0;

    collection.sendDeployNftV12(
        manager.address,
        queryId,
        itemIndex,
        grams("0.02"),
        owner.address,
        "ack.json",
        { value: grams("0.1"), bounce: true },
    );

    val result = collection.sendNftItemDeploymentAckV12(
        attacker.address,
        queryId,
        itemIndex,
        { value: grams("0.03"), bounce: true },
    );

    expect(result).toHaveFailedTx<NftItemDeploymentAckV12>({
        from: attacker.address,
        to: collection.address,
        exitCode: NftV12Errors.NotFromManager,
    });
}

get fun `test nft v1.2: rejects zero deployment query id`() {
    val (collection, manager, owner) = setupNftCollectionV12Test();

    val result = collection.sendDeployNftV12(
        manager.address,
        0,
        0,
        grams("0.02"),
        owner.address,
        "zero-query-id.json",
        { value: grams("0.1"), bounce: true },
    );

    expect(result).toHaveFailedTx<DeployNftV12>({
        from: manager.address,
        to: collection.address,
        exitCode: NftV12Errors.InvalidDeploymentState,
    });
}
