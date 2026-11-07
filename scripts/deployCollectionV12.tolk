import "utils/common-v12"

fun main() {
    val deployer = promptNftWalletV12("Connect TagitalSpace Testnet deployer wallet");
    val info = promptNftCollectionInfoV12();
    val collection = deployNftCollectionV12(deployer, info);
    printNftCollectionV12Info(collection);
}
