import XCTest
@testable import MarketKit

final class ThwalletXrpCatalogTests: XCTestCase {
    func testCanonicalIdentityAndNativeQueryRoundTrip() {
        XCTAssertEqual(BlockchainType.ripple.uid, "ripple")
        XCTAssertEqual(BlockchainType(uid: "ripple"), .ripple)

        let query = TokenQuery(blockchainType: .ripple, tokenType: .native)
        XCTAssertEqual(query.id, "ripple|native")
        XCTAssertEqual(TokenQuery(id: query.id), query)
    }

    func testNormalizationRepairsMissingNativeDecimalsAndMetadata() {
        let normalized = ThwalletXrpCatalog.normalize(
            coins: [Coin(uid: "ripple", name: "Old XRP", code: "xrp")],
            blockchainRecords: [BlockchainRecord(uid: "ripple", name: "Old Ripple", explorerUrl: nil)],
            tokenRecords: [TokenRecord(coinUid: "ripple", blockchainUid: "ripple", type: "native", decimals: nil)]
        )

        XCTAssertEqual(normalized.coins.filter { $0.uid == "ripple" }.count, 1)
        XCTAssertEqual(normalized.coins.first { $0.uid == "ripple" }?.name, "XRP")
        XCTAssertEqual(normalized.coins.first { $0.uid == "ripple" }?.code, "XRP")
        XCTAssertEqual(normalized.blockchainRecords.filter { $0.uid == "ripple" }.count, 1)
        XCTAssertEqual(
            normalized.blockchainRecords.first { $0.uid == "ripple" }?.explorerUrl,
            "https://xrpscan.com/account/$ref"
        )

        let nativeRows = normalized.tokenRecords.filter { $0.blockchainUid == "ripple" && $0.type == "native" }
        XCTAssertEqual(nativeRows.count, 1)
        XCTAssertEqual(nativeRows.first?.coinUid, "ripple")
        XCTAssertEqual(nativeRows.first?.decimals, 6)
    }

    func testNormalizationIsIdempotent() {
        let initial = ThwalletXrpCatalog.normalize(coins: [], blockchainRecords: [], tokenRecords: [])
        let repeated = ThwalletXrpCatalog.normalize(
            coins: initial.coins,
            blockchainRecords: initial.blockchainRecords,
            tokenRecords: initial.tokenRecords
        )

        XCTAssertEqual(repeated.coins.filter { $0.uid == "ripple" }.count, 1)
        XCTAssertEqual(repeated.blockchainRecords.filter { $0.uid == "ripple" }.count, 1)
        XCTAssertEqual(repeated.tokenRecords.filter { $0.blockchainUid == "ripple" && $0.type == "native" }.count, 1)
    }
}
