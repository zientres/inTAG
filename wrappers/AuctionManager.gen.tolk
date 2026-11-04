// Wrapper for contract 'AuctionManager'

import "@acton/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@contracts/auction-manager/types"

struct AuctionManager {
    address: address
    stateInit: ContractState? = null
}

fun AuctionManager.fromStorage(
    storage: AuctionManagerStorage,
    toShard: AddressShardingOptions? = null,
): AuctionManager {
    val stateInit = ContractState {
        code: build("AuctionManager"),
        data: storage.toCell(),
    };
    val address = AutoDeployAddress { stateInit, toShard }.calculateAddress();
    return AuctionManager { address, stateInit };
}

fun AuctionManager.fromAddress(address: address): AuctionManager {
    return AuctionManager { address };
}

fun AuctionManager.deploy(
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

fun AuctionManager.sendAny(
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

fun AuctionManager.getAuction(self, auctionId: uint64): AuctionV1? {
    return net.runGetMethod(self.address, "get_auction", [auctionId]);
}

fun AuctionManager.getRefundCredit(self, beneficiary: address): coins {
    return net.runGetMethod(self.address, "get_refund_credit", [beneficiary]);
}

fun AuctionManager.getPayoutCredit(self, beneficiary: address): coins {
    return net.runGetMethod(self.address, "get_payout_credit", [beneficiary]);
}
