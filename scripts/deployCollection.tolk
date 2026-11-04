import "utils/common"

fun main() {
    val deployer = promptNftWallet("Connect TagitalSpace Testnet deployer wallet");
    val info = promptNftCollectionInfo();
    val collection = deployNftCollection(deployer, info);
    printNftCollectionInfo(collection);
}
