// Auto-generated wrapper for contract 'NftItemV12'
// Generated for the TagitalSpace verified-mint collection contract.

import "@acton/build"
import "@acton/emulation/network"
import "@contracts/nft-v1.1/messages"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/types"

struct NftItemV12 {
    address: address
    stateInit: ContractState? = null
}

fun NftItemV12.fromStorage(
    storage: NftItemV12StorageNotInitialized,
    toShard: AddressShardingOptions? = null,
): NftItemV12 {
    val stateInit = ContractState {
        code: build("NftItemV12"),
        data: storage.toCell(),
    };
    val address = AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return NftItemV12 { address, stateInit };
}

fun NftItemV12.fromAddress(address: address): NftItemV12 {
    return NftItemV12 { address };
}

fun NftItemV12.sendAskToChangeOwnership(
    self,
    from: address,
    queryId: uint64,
    newOwnerAddress: address,
    sendExcessesTo: address?,
    customPayload: cell?,
    forwardTonAmount: coins,
    forwardPayload: PayloadInline | PayloadInRef,
    config: SendParams = {},
): SendResultList {
    val bodyB = beginCell()
        .storeUint(0x5fcc3d14, 32)
        .storeAny(queryId)
        .storeAny(newOwnerAddress)
        .storeAny(sendExcessesTo)
        .storeAny(customPayload)
        .storeAny(forwardTonAmount)
        .storeAny(forwardPayload);
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: AskToChangeOwnership.fromSlice(bodyB.toSlice()),
    });
    return net.send(from, genericMsg);
}

fun NftItemV12.sendRequestStaticData(
    self,
    from: address,
    queryId: uint64,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: RequestStaticData { queryId },
    });
    return net.send(from, genericMsg);
}

fun NftItemV12.sendAny(
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

fun NftItemV12.getNftData(self): NftDataReplyV12 {
    return net.runGetMethod(self.address, "get_nft_data");
}
