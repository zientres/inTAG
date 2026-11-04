import "@stdlib/strings"
import "@acton/build"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/scripts"
import "@acton/testing/assert"

import "@wrappers/NftCollection.gen"
import "@wrappers/NftItem.gen"

const NFT_ITEM_DEPLOY_AMOUNT = grams("0.02")
const NFT_COLLECTION_MESSAGE_VALUE = grams("0.08")

fun main() {
    val wallet = scripts.wallet(promptWallet("Connect TagitalSpace Testnet admin wallet"));
    val collectionAddress = promptAddress("TagitalSpace NFT Collection address");
    val collection = NftCollection.fromAddress(collectionAddress);

    val collectionData = collection.getCollectionData();
    if (wallet.address != collectionData.adminAddress) {
        Assert.fail("Connected wallet is not the NFT collection admin");
    }

    val itemIndex = collectionData.nextItemIndex;
    val itemContent = StringBuilder
        .create()
        .append(itemIndex.toDecimalString())
        .append(".json")
        .build();
    val ownerAddress = promptAddress("NFT recipient wallet address");

    println("Collection: {}", collectionAddress);
    println("NFT index: {}", itemIndex);
    println("Metadata URL: {}/{}", "https://zientres.github.io/inTAG/metadata", itemContent);
    println("Recipient: {}", ownerAddress);
    println("Attached value: {:grams}", NFT_ITEM_DEPLOY_AMOUNT);

    if (
        !confirm(
            "Have you published this NFT's JSON metadata and unique plate image? Continue with Testnet mint?",
            false,
            "This sends a real transaction on TON Testnet. The recipient will receive the NFT.",
        )
    ) {
        println("Mint cancelled. No transaction was sent.");
        return;
    }

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

    if (!nftData.isInitialized) {
        Assert.fail("NFT item deployment was not confirmed");
    }
    if (nftData.itemIndex != itemIndex) {
        Assert.fail("NFT item index mismatch");
    }
    if (nftData.ownerAddress! != ownerAddress) {
        Assert.fail("NFT owner mismatch");
    }
    if (nftData.collectionAddress != collectionAddress) {
        Assert.fail("NFT collection mismatch");
    }

    println("NFT_MINTED=true");
    println("NFT_INDEX={}", itemIndex);
    println("NFT_ADDRESS={}", nftAddress);
    println("NFT_OWNER={}", ownerAddress);
    println("NFT_METADATA={}/{}", "https://zientres.github.io/inTAG/metadata", itemContent);
}
