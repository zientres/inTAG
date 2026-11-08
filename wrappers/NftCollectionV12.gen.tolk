// Auto-generated wrapper for contract 'NftCollectionV12'
// Generated for the TagitalSpace verified-mint collection contract.

import "@acton/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/messages"
import "@contracts/nft-v1.2/types"

struct NftCollectionV12 {
    address: address
    stateInit: ContractState? = null
}

fun NftCollectionV12.fromStorage(
    storage: NftCollectionV12Storage,
    toShard: AddressShardingOptions? = null,
): NftCollectionV12 {
    val stateInit = ContractState {
        code: build("NftCollectionV12"),
        data: storage.toCell(),
    };
    val address = AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return NftCollectionV12 { address, stateInit };
}

fun NftCollectionV12.fromAddress(address: address): NftCollectionV12 {
    return NftCollectionV12 { address };
}

fun NftCollectionV12.deploy(
    self,
    from: address,
    config: SendParams = {},
): SendResultList {
    if (self.stateInit == null) {
        Assert.fail("Cannot deploy a contract created with 'fromAddress' because it lacks state init for deployment");
    }
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: { stateInit: self.stateInit },
    });
    return net.send(from, genericMsg);
}

fun NftCollectionV12.sendRequestRoyaltyParams(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: RequestRoyaltyParams { queryId },
    });
    return net.send(from, genericMsg);
}

fun NftCollectionV12.sendDeployNftV12(
    self,
    from: address,
    queryId: uint64,
    itemIndex: uint64,
    attachTonAmount: coins,
    ownerAddress: address,
    content: cell,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: DeployNftV12 { queryId, itemIndex, attachTonAmount, ownerAddress, content },
    });
    return net.send(from, genericMsg);
}

fun NftCollectionV12.sendNftItemDeploymentAckV12(
    self,
    from: address,
    queryId: uint64,
    itemIndex: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: NftItemDeploymentAckV12 { queryId, itemIndex },
    });
    return net.send(from, genericMsg);
}

fun NftCollectionV12.sendRetryNftItemDeploymentNoticeV12(
    self,
    from: address,
    queryId: uint64,
    itemIndex: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: RetryNftItemDeploymentNoticeV12 { queryId, itemIndex },
    });
    return net.send(from, genericMsg);
}

fun NftCollectionV12.sendChangeCollectionAdmin(
    self,
    from: address,
    queryId: uint64,
    newAdminAddress: address,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: ChangeCollectionAdmin { queryId, newAdminAddress },
    });
    return net.send(from, genericMsg);
}

fun NftCollectionV12.sendAny(
    self,
    from: address,
    body: cell,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body,
    });
    return net.send(from, genericMsg);
}

fun NftCollectionV12.getCollectionData(self): CollectionDataReply {
    return net.runGetMethod(self.address, "get_collection_data");
}

fun NftCollectionV12.getNftAddressByIndex(self, itemIndex: int): address {
    return net.runGetMethod(self.address, "get_nft_address_by_index", [itemIndex]);
}

fun NftCollectionV12.royaltyParams(self): RoyaltyParams {
    return net.runGetMethod(self.address, "royalty_params");
}

fun NftCollectionV12.getNftContent(
    self,
    itemIndex: int,
    individualNftContent: cell,
): cell {
    return net.runGetMethod(self.address, "get_nft_content", [itemIndex, individualNftContent]);
}

fun NftCollectionV12.getPendingNftDeployment(
    self,
    itemIndex: uint64,
): PendingNftDeploymentV12? {
    return net.runGetMethod(self.address, "get_pending_nft_deployment", [itemIndex]);
}
