import "@stdlib/strings"
import "@acton/build"
import "@acton/io"
import "@acton/prompts"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@wrappers/NftCollectionV12.gen"
import "@contracts/nft-v1.1/types"
import "@contracts/nft-v1.2/types"

const ONCHAIN_CONTENT_PREFIX_V12 = 0x00
const COLLECTION_IMAGE_URL_V12 = "https://zientres.github.io/inTAG/logo.png"
const NFT_METADATA_BASE_URL_V12 = "https://zientres.github.io/inTAG/metadata/"

struct NftCollectionV12Info {
    name: string
    description: string
    image: string
    commonContent: string
}

fun buildOnchainMetadataV12(info: NftCollectionV12Info): cell {
    var dict: map<uint256, string_prefixed0x> = [];
    dict.set("name".sha256(), info.name.prefixWith00());
    dict.set("description".sha256(), info.description.prefixWith00());
    dict.set("image".sha256(), info.image.prefixWith00());
    return beginCell()
        .storeUint(ONCHAIN_CONTENT_PREFIX_V12, 8)
        .storeDict(dict.toLowLevelDict())
        .endCell();
}

fun promptNftWalletV12(message: string): ActonWallet {
    return scripts.wallet(promptWallet(message));
}

fun promptNftCollectionInfoV12(): NftCollectionV12Info {
    return {
        name: prompt("Collection name", "", "TagitalSpace"),
        description: prompt(
            "Collection description",
            "",
            "Digital license plate collectibles from around the world",
        ),
        image: prompt("Collection image URL", "", COLLECTION_IMAGE_URL_V12),
        commonContent: prompt(
            "Base URL for NFT item JSON metadata (must end with /)",
            "",
            NFT_METADATA_BASE_URL_V12,
        ),
    };
}

fun makeNftCollectionV12Storage(
    admin: address,
    info: NftCollectionV12Info,
): NftCollectionV12Storage {
    return {
        adminAddress: admin,
        nextItemIndex: 0,
        content: CollectionContent {
            collectionMetadata: buildOnchainMetadataV12(info),
            commonContent: info.commonContent,
        }.toCell(),
        nftItemCode: build("NftItemV12"),
        royaltyParams: RoyaltyParams {
            numerator: 2,
            denominator: 100,
            royaltyAddress: admin,
        }.toCell(),
        pendingDeployments: [],
    };
}

fun deployNftCollectionV12(
    deployer: ActonWallet,
    info: NftCollectionV12Info,
): NftCollectionV12 {
    val collection = NftCollectionV12.fromStorage(
        makeNftCollectionV12Storage(deployer.address, info),
    );
    val result = collection.deploy(deployer.address, { value: grams("0.2"), bounce: false });
    result.waitForFirstTransaction();
    return collection;
}

fun printNftCollectionV12Info(collection: NftCollectionV12) {
    val data = collection.getCollectionData();
    val royalty = collection.royaltyParams();
    println("COLLECTION_V12_ADDRESS={}", collection.address);
    println("ADMIN_ADDRESS={}", data.adminAddress);
    println("NEXT_ITEM_INDEX={}", data.nextItemIndex);
    println("ROYALTY_ADDRESS={}", royalty.royaltyAddress);
    println("ROYALTY_NUMERATOR={}", royalty.numerator);
    println("ROYALTY_DENOMINATOR={}", royalty.denominator);
}
