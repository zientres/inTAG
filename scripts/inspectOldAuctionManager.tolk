import "@acton/io"
import "@acton/prompts"
import "@wrappers/AuctionManager.gen"

const MAX_AUCTIONS_TO_SCAN = 1000

fun main() {
    val manager = AuctionManager.fromAddress(
        promptAddress("Enter old Auction Manager Testnet address"),
    );

    val nextItemIndex = manager.getNextItemIndex();
    val treasuryBalance = manager.getTreasuryBalance();

    println("MANAGER_ADDRESS={}", manager.address);
    println("NEXT_ITEM_INDEX={}", nextItemIndex);
    println("TREASURY_BALANCE_NANO={}", treasuryBalance);

    var scanCount = nextItemIndex;
    if (scanCount > MAX_AUCTIONS_TO_SCAN) {
        scanCount = MAX_AUCTIONS_TO_SCAN;
        println("WARNING=SCAN_LIMIT_REACHED");
    }

    var index: uint64 = 0;
    while (index < scanCount) {
        val auction = manager.getAuction(index);
        if (auction != null) {
            println("AUCTION_ID={}", index);
            println("PLATE={}", auction!!.plate);
            println("STATUS={}", auction!!.status);
            println("STARTING_BID_NANO={}", auction!!.startingBid);
            println("MINIMUM_BID_STEP_NANO={}", auction!!.minimumBidStep);
            println("END_TIME={}", auction!!.endTime);
            println("HIGHEST_BID_NANO={}", auction!!.highestBid);
            println("HIGHEST_BIDDER={}", auction!!.highestBidder);
            println("MINT_QUERY_ID={}", auction!!.mintQueryId);
            if (auction!!.highestBidder != null) {
                val bidder = auction!!.highestBidder!!;
                println("BIDDER_REFUND_CREDIT_NANO={}", manager.getRefundCredit(bidder));
                println("BIDDER_PAYOUT_CREDIT_NANO={}", manager.getPayoutCredit(bidder));
            }
        }
        index += 1;
    }

    println("SCAN_COMPLETE=TRUE");
    println("NOTE=LOCKED_FUNDS_AND_FULL_CREDIT_MAPS_REQUIRE_STORAGE_DECODE");
}
