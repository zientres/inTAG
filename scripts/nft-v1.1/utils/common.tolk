import "@stdlib/strings"
import "@acton/build"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "../../contracts/nft-v1.1/messages"
import "../../contracts/nft-v1.1/types"
import "../../wrappers/NftCollection.gen"
import "../../wrappers/NftItem.gen"

const ONCHAIN_CONTENT_PREFIX = 0x00

struct NftCollectionInfo {
    name: string
    description: string
    image: string
    commonContent: string
}

fun buildOnchainMetadata(info: NftCollectionInfo): cell {
    var dict: map<uint256, string_prefixed0x> = [];
    dict.set("name".sha256(), info.name.prefixWith00());
    dict.set("description".sha256(), info.description.prefixWith00());
    dict.set("image".sha256(), info.image.prefixWith00());
    return beginCell()
        .storeUint(ONCHAIN_CONTENT_PREFIX, 8)
        .storeDict(dict.toLowLevelDict())
        .endCell();
}

fun promptNftWallet(message: string): ActonWallet {
    return scripts.wallet(promptWallet(message));
}

fun promptNftCollectionInfo(): NftCollectionInfo {
    return {
        name: prompt("Collection name", "", "TagitalSpace"),
        description: prompt("Collection description", "", "Digital license plate collectibles from around the world"),
        image: prompt("Collection image URL", "", ""),
        commonContent: prompt("Base URL for NFT item JSON metadata (must end with /)", "", ""),
    };
}

fun makeNftCollectionStorage(admin: address, info: NftCollectionInfo): NftCollectionStorage {
    return {
        adminAddress: admin,
        nextItemIndex: 0,
        content: CollectionContent {
            collectionMetadata: buildOnchainMetadata(info),
            commonContent: info.commonContent,
        }.toCell(),
        nftItemCode: build("NftItem"),
        royaltyParams: RoyaltyParams {
            numerator: 2,
            denominator: 100,
            royaltyAddress: admin,
        }.toCell(),
    };
}

fun deployNftCollection(deployer: ActonWallet, info: NftCollectionInfo): NftCollection {
    assert (info.commonContent != "") throw 1001;
    assert (info.image != "") throw 1002;
    val collection = NftCollection.fromStorage(makeNftCollectionStorage(deployer.address, info));
    val res = collection.deploy(deployer.address, { value: grams("0.2"), bounce: false });
    res.waitForFirstTransaction();
    return collection;
}

fun printNftCollectionInfo(collection: NftCollection) {
    val data = collection.getCollectionData();
    val royalty = collection.royaltyParams();
    println("COLLECTION_ADDRESS={}", collection.address);
    println("ADMIN_ADDRESS={}", data.adminAddress);
    println("NEXT_ITEM_INDEX={}", data.nextItemIndex);
    println("ROYALTY_ADDRESS={}", royalty.royaltyAddress);
    println("ROYALTY_NUMERATOR={}", royalty.numerator);
    println("ROYALTY_DENOMINATOR={}", royalty.denominator);
}
