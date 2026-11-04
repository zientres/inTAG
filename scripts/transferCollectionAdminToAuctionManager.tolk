import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/NftCollectionV12.gen"
import "@contracts/nft-v1.1/messages"

fun main() {
    val currentAdmin = scripts.wallet(promptWallet("Connect current NFT collection admin wallet"));
    val collection = NftCollectionV12.fromAddress(
        promptAddress("Enter NFT Collection v1.2 Testnet address"),
    );
    val managerAddress = promptAddress("Enter Auction Manager Testnet address");

    val result = collection.sendAny(
        currentAdmin.address,
        ChangeCollectionAdmin {
            queryId: 1,
            newAdminAddress: managerAddress,
        }.toCell(),
        { value: grams("0.05"), bounce: true },
    );
    result.waitForFirstTransaction();
    println("COLLECTION_ADMIN_TRANSFER_SUBMITTED");
    println("COLLECTION_ADDRESS={}", collection.address);
    println("NEW_ADMIN_ADDRESS={}", managerAddress);
}
