import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/AuctionManager.gen"

fun main() {
    val owner = scripts.wallet(promptWallet("Connect Auction Manager owner wallet"));
    val manager = AuctionManager.fromAddress(
        promptAddress("Enter Auction Manager Testnet address"),
    );
    val securityFund = promptAddress("Enter development and security fund wallet address");

    val result = manager.sendSetPayoutAddressesV1(
        owner.address,
        1,
        securityFund,
        { value: grams("0.05"), bounce: true },
    );
    result.waitForFirstTransaction();
    println("PAYOUT_CONFIGURATION_SUBMITTED");
    println("SECURITY_FUND_ADDRESS={}", securityFund);
}
