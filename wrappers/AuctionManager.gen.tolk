// Wrapper for contract 'AuctionManager'

import "@acton/build"
import "@acton/emulation/network"
import "@acton/testing/assert"
import "@contracts/auction-manager/messages"
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

fun AuctionManager.getNextItemIndex(self): uint64 {
    return net.runGetMethod(self.address, "get_next_item_index", []);
}

fun AuctionManager.getAuctionSummary(self, auctionId: uint64): cell? {
    return net.runGetMethod(self.address, "get_auction_summary", [auctionId]);
}

fun AuctionManager.getPlateStatus(self, plateHash: uint256): int {
    return net.runGetMethod(self.address, "get_plate_status", [plateHash]);
}

fun AuctionManager.getRefundCredit(self, beneficiary: address): coins {
    return net.runGetMethod(self.address, "get_refund_credit", [beneficiary]);
}

fun AuctionManager.getTreasuryBalance(self): coins {
    return net.runGetMethod(self.address, "get_treasury_balance", []);
}

fun AuctionManager.getPayoutCredit(self, beneficiary: address): coins {
    return net.runGetMethod(self.address, "get_payout_credit", [beneficiary]);
}

fun AuctionManager.sendSetPayoutAddressesV1(
    self,
    from: address,
    queryId: uint64,
    securityFundAddress: address,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: SetPayoutAddressesV1 { queryId, securityFundAddress },
    });
    return net.send(from, genericMsg);
}

fun AuctionManager.sendWithdrawTreasuryV1(
    self,
    from: address,
    queryId: uint64,
    amount: coins,
    config: SendParams = {},
): SendResultList {
    val genericMsg = createMessage({
        bounce: config.bounce,
        value: config.value,
        dest: self.address,
        body: WithdrawTreasuryV1 { queryId, amount },
    });
    return net.send(from, genericMsg);
}
