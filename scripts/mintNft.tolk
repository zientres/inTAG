import "@acton/build"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@acton/testing/assert"

import "@wrappers/NftCollection.gen"
import "@wrappers/NftItem.gen"
import "@contracts/nft-v1.1/messages"

const NFT_ITEM_DEPLOY_AMOUNT = grams("0.02")
const NFT_COLLECTION_MESSAGE_VALUE = grams("0.08")

fun main() {
    val wallet = scripts.wallet(promptWallet("Connect TagitalSpace Testnet admin wallet"));
    val collectionAddress = promptAddress("TagitalSpace NFT Collection address");
    val collection = NftCollection.fromAddress(collectionAddress);

    val collectionData = collection.getCollectionData();
    assert (wallet.address == collectionData.adminAddress) throw "Connected wallet is not collection admin";

    val itemIndex = collectionData.nextItemIndex;
    val itemContent = prompt(
        "NFT metadata filename (must already be published)",
        "",
        itemIndex.toString() + ".json",
    );

    assert (itemContent != "") throw "NFT metadata filename cannot be empty";
    assert (itemContent.endsWith(".json")) throw "NFT content must be a JSON filename";
    assert (!itemContent.contains("/")) throw "Use only a filename, not a path";

    val ownerAddress = promptAddress("NFT recipient wallet address");
    println("Collection: {}", collectionAddress);
    println("NFT index: {}", itemIndex);
    println("Metadata URL: {}/{}", "https://zientres.github.io/inTAG/metadata", itemContent);
    println("Recipient: {}", ownerAddress);
    println("Attached value: {} TON", NFT_ITEM_DEPLOY_AMOUNT);
    assert (confirm("Metadata JSON and its unique plate image are already published. Continue with Testnet mint?", false)) throw "Mint cancelled by user";

    val result = collection.sendDeployNft(
        wallet.address,
        0,
        itemIndex,
        NFT_ITEM_DEPLOY_AMOUNT,
        { ownerAddress, content: itemContent },
        { value: NFT_COLLECTION_MESSAGE_VALUE, bounce: true },
    );
    val trace = result.waitForTrace();
    if (trace == null) {
        Assert.fail("Could not confirm NFT mint transaction on Testnet. Check the collection and wallet state before retrying.");
    }

    val nftAddress = collection.getNftAddressByIndex(itemIndex);
    val item = NftItem.fromAddress(nftAddress);
    val nftData = item.getNftData();

    assert (nftData.isInitialized) throw "NFT item deployment was not confirmed";
    assert (nftData.itemIndex == itemIndex) throw "NFT item index mismatch";
    assert (nftData.ownerAddress! == ownerAddress) throw "NFT owner mismatch";
    assert (nftData.collectionAddress == collectionAddress) throw "NFT collection mismatch";

    println("NFT_MINTED=true");
    println("NFT_INDEX={}", itemIndex);
    println("NFT_ADDRESS={}", nftAddress);
    println("NFT_OWNER={}", ownerAddress);
    println("NFT_METADATA={}/{}", "https://zientres.github.io/inTAG/metadata", itemContent);
}
