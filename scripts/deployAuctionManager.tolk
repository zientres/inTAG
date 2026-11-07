import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/AuctionManager.gen"
import "@contracts/auction-manager/types"

fun main() {
    val deployer = scripts.wallet(promptWallet("Connect Auction Manager Testnet owner wallet"));
    val collectionAddress = promptAddress("Enter the compatible NFT Collection v1.2 Testnet address");

    val manager = AuctionManager.fromStorage({
        ownerAddress: deployer.address,
        collectionAddress,
        payoutConfigLocked: false,
        nextItemIndex: 0,
        nextMintItemIndex: 0,
        nextQueryId: 1,
        auctions: [],
        refundCredits: [],
        payoutCredits: [],
        treasuryBalance: 0,
        lockedFunds: 0,
        plateToAuctionId: [],
        securityFundAddress: null,
    });

    val result = manager.deploy(
        deployer.address,
        { value: grams("0.2"), bounce: false },
    );
    result.waitForFirstTransaction();

    println("AUCTION_MANAGER_ADDRESS={}", manager.address);
    println("OWNER_ADDRESS={}", deployer.address);
    println("COLLECTION_ADDRESS={}", collectionAddress);
    println("PAYOUT_ADDRESSES=NOT_CONFIGURED");
}
