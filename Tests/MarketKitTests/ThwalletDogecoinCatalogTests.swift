import Foundation
import GRDB
import XCTest
@testable import MarketKit

final class ThwalletDogecoinCatalogTests: XCTestCase {
    func testBlockchainTypeAndNativeTokenRoundTripThroughStorage() throws {
        XCTAssertEqual(BlockchainType.dogecoin.uid, "dogecoin")
        XCTAssertEqual(BlockchainType(uid: "dogecoin"), .dogecoin)

        let normalized = ThwalletDogecoinCatalog.normalize(
            coins: [],
            blockchainRecords: [],
            tokenRecords: []
        )
        let query = TokenQuery(blockchainType: .dogecoin, tokenType: .native)

        XCTAssertEqual(query.id, "dogecoin|native")
        XCTAssertEqual(TokenQuery(id: query.id), query)

        try withTemporaryStorage { storage in
            try storage.update(
                coins: normalized.coins,
                blockchainRecords: normalized.blockchainRecords,
                tokenRecords: normalized.tokenRecords
            )

            let token = try XCTUnwrap(storage.tokenInfoRecord(query: query)?.token)
            XCTAssertEqual(token.blockchainType, .dogecoin)
            XCTAssertEqual(token.blockchain.name, "Dogecoin")
            XCTAssertEqual(token.blockchain.explorerUrl, "https://blockchair.com/dogecoin/address/$ref")
            XCTAssertEqual(token.coin.uid, "dogecoin")
            XCTAssertEqual(token.coin.name, "Dogecoin")
            XCTAssertEqual(token.coin.code, "DOGE")
            XCTAssertEqual(token.decimals, 8)
        }
    }

    func testNormalizationIsIdempotentAndKeepsOneAuthoritativeNativeRow() {
        let first = ThwalletDogecoinCatalog.normalize(
            coins: [
                Coin(uid: "dogecoin", name: "Old Doge", code: "doge", marketCapRank: 9, image: "doge.png"),
            ],
            blockchainRecords: [
                BlockchainRecord(uid: "dogecoin", name: "Old Dogecoin", explorerUrl: nil),
            ],
            tokenRecords: [
                TokenRecord(coinUid: "dogecoin", blockchainUid: "dogecoin", type: "native", decimals: 18),
                TokenRecord(coinUid: "wrong-doge", blockchainUid: "dogecoin", type: "native", decimals: 8),
            ]
        )
        let second = ThwalletDogecoinCatalog.normalize(
            coins: first.coins,
            blockchainRecords: first.blockchainRecords,
            tokenRecords: first.tokenRecords
        )

        XCTAssertEqual(snapshot(first), snapshot(second))
        XCTAssertEqual(second.coins.filter { $0.uid == "dogecoin" }.count, 1)
        XCTAssertEqual(second.blockchainRecords.filter { $0.uid == "dogecoin" }.count, 1)

        let nativeRows = second.tokenRecords.filter { $0.blockchainUid == "dogecoin" && $0.type == "native" }
        XCTAssertEqual(nativeRows.count, 1)
        XCTAssertEqual(nativeRows.first?.coinUid, "dogecoin")
        XCTAssertEqual(nativeRows.first?.decimals, 8)
        XCTAssertNil(nativeRows.first?.reference)
    }

    private func snapshot(_ data: ThwalletDogecoinCatalog.NormalizedData) -> [String] {
        let coins = data.coins.map {
            "coin|\($0.uid)|\($0.name)|\($0.code)|\($0.marketCapRank.map { String($0) } ?? "nil")|\($0.coinGeckoId ?? "nil")|\($0.image ?? "nil")"
        }
        let blockchains = data.blockchainRecords.map {
            "blockchain|\($0.uid)|\($0.name)|\($0.explorerUrl ?? "nil")"
        }
        let tokens = data.tokenRecords.map {
            "token|\($0.coinUid)|\($0.blockchainUid)|\($0.type)|\($0.decimals.map { String($0) } ?? "nil")|\($0.reference ?? "nil")"
        }

        return coins + blockchains + tokens
    }
}
