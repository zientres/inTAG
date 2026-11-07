import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@wrappers/NftCollectionV12.gen"
import "@wrappers/NftItemV12.gen"
import "@contracts/nft-v1.1/errors"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/messages"
import "@contracts/nft-v1.2/types"

fun setupNftItemV12Test(): (NftCollectionV12, Treasury, Treasury, NftItemV12) {
    val manager = testing.treasury("nft-v12-manager");
    val owner = testing.treasury("nft-v12-owner");
    val receiver = testing.treasury("nft-v12-receiver");
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
        completedSkips: [],
    });

    val deployCollection = collection.deploy(
        manager.address,
        { value: grams("0.2"), bounce: false },
    );
    expect(deployCollection).toHaveSuccessfulDeploy({ to: collection.address });

    collection.sendDeployNftV12(
        manager.address,
        12001,
        0,
        grams("0.02"),
        owner.address,
        "0.json",
        { value: grams("0.1"), bounce: true },
    );

    val itemAddress = collection.getNftAddressByIndex(0);
    val item = NftItemV12.fromAddress(itemAddress);
    expect(item.getNftData().isInitialized).toBeTrue();

    return (collection, owner, receiver, item);
}

get fun `test nft v1.2 item: transfers ownership and preserves initialization data`() {
    val (collection, owner, receiver, item) = setupNftItemV12Test();

    val transfer = item.sendAskToChangeOwnership(
        owner.address,
        42,
        receiver.address,
        null,
        null,
        0,
        PayloadInline { value: createEmptySlice() },
        { value: grams("0.05"), bounce: true },
    );

    expect(transfer).toHaveSuccessfulTx<AskToChangeOwnership>({
        from: owner.address,
        to: item.address,
    });
    expect(item.getNftData().ownerAddress!).toEqual(receiver.address);

    val retry = collection.sendRetryNftItemDeploymentNoticeV12(
        testing.treasury("nft-v12-manager").address,
        12001,
        0,
        { value: grams("0.03"), bounce: true },
    );
    expect(retry).toHaveTx<NftItemDeploymentConfirmedV12>({
        from: collection.address,
    });
}

get fun `test nft v1.2 item: rejects transfer from non-owner`() {
    val (_, owner, receiver, item) = setupNftItemV12Test();
    val attacker = testing.treasury("nft-v12-attacker");

    val result = item.sendAskToChangeOwnership(
        attacker.address,
        43,
        receiver.address,
        null,
        null,
        0,
        PayloadInline { value: createEmptySlice() },
        { value: grams("0.05"), bounce: true },
    );

    expect(result).toHaveFailedTx<AskToChangeOwnership>({
        from: attacker.address,
        to: item.address,
        exitCode: Errors.NotFromOwner,
    });
    expect(item.getNftData().ownerAddress!).toEqual(owner.address);
}

get fun `test nft v1.2 item: rejects receiver in another workchain`() {
    val (_, owner, _, item) = setupNftItemV12Test();
    val invalidReceiver = randomAddress("nft-v12-invalid-workchain", -1);

    val result = item.sendAskToChangeOwnership(
        owner.address,
        44,
        invalidReceiver,
        null,
        null,
        0,
        PayloadInline { value: createEmptySlice() },
        { value: grams("0.05"), bounce: true },
    );

    expect(result).toHaveFailedTx<AskToChangeOwnership>({
        from: owner.address,
        to: item.address,
        exitCode: Errors.InvalidWorkchain,
    });
    expect(item.getNftData().ownerAddress!).toEqual(owner.address);
}

get fun `test nft v1.2 item: returns TEP-62 static data`() {
    val (collection, _, _, item) = setupNftItemV12Test();
    val requester = testing.treasury("nft-v12-static-data-requester");
    val queryId = 12002;
    val nftData = item.getNftData();

    val result = item.sendRequestStaticData(
        requester.address,
        queryId,
        { value: grams("0.05"), bounce: true },
    );

    expect(result).toHaveSuccessfulTx<RequestStaticData>({
        from: requester.address,
        to: item.address,
    });
    expect(result).toHaveTx<ResponseStaticData>({
        from: item.address,
        to: requester.address,
        bounce: false,
        body: ResponseStaticData {
            queryId,
            itemIndex: nftData.itemIndex,
            collectionAddress: collection.address,
        }.toCell(),
    });
}

get fun `test nft v1.2 item: forwards TON to the new owner`() {
    val (_, owner, receiver, item) = setupNftItemV12Test();
    val forwardAmount = grams("0.02");
    val forwardPayload = beginCell().storeUint(0, 32).storeString("Forwarded").endCell();
    val expectedForwardPayload = beginCell()
        .storeBool(true)
        .storeRef(forwardPayload)
        .toSlice() as RemainingBitsAndRefs;
    val queryId = 45;

    val result = item.sendAskToChangeOwnership(
        owner.address,
        queryId,
        receiver.address,
        null,
        null,
        forwardAmount,
        PayloadInRef { value: forwardPayload as Cell<RemainingBitsAndRefs> },
        { value: grams("0.1"), bounce: true },
    );

    expect(result).toHaveSuccessfulTx<AskToChangeOwnership>({
        from: owner.address,
        to: item.address,
    });
    expect(result).toHaveTx<NotificationForNewOwner>({
        from: item.address,
        to: receiver.address,
        value: forwardAmount,
        bounce: false,
        body: NotificationForNewOwner {
            queryId,
            oldOwnerAddress: owner.address,
            payload: expectedForwardPayload,
        }.toCell(),
    });
    expect(item.getNftData().ownerAddress!).toEqual(receiver.address);
}

get fun `test nft v1.2 item: returns excesses to the requested address`() {
    val (_, owner, receiver, item) = setupNftItemV12Test();
    val excessesReceiver = testing.treasury("nft-v12-excesses-receiver");
    val queryId = 46;

    val result = item.sendAskToChangeOwnership(
        owner.address,
        queryId,
        receiver.address,
        excessesReceiver.address,
        null,
        0,
        PayloadInline { value: createEmptySlice() },
        { value: grams("0.1"), bounce: true },
    );

    expect(result).toHaveSuccessfulTx<AskToChangeOwnership>({
        from: owner.address,
        to: item.address,
    });
    expect(result).toHaveTx<ReturnExcessesBack>({
        from: item.address,
        to: excessesReceiver.address,
        bounce: false,
        body: ReturnExcessesBack { queryId }.toCell(),
    });
    expect(item.getNftData().ownerAddress!).toEqual(receiver.address);
}
