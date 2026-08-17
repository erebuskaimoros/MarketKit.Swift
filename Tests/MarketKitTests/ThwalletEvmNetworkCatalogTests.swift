import Foundation
import GRDB
import XCTest
@testable import MarketKit

final class ThwalletEvmNetworkCatalogTests: XCTestCase {
    func testNormalizesCompleteContractsAndInjectsNativeRows() {
        let validContract = TokenRecord(
            coinUid: "usd-coin",
            blockchainUid: "blast",
            type: "blast",
            decimals: 6,
            reference: "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
        )
        let unsafeContract = TokenRecord(
            coinUid: "tether",
            blockchainUid: "cronos",
            type: "cronos"
        )
        let mantlePseudoNative = TokenRecord(
            coinUid: "mantle",
            blockchainUid: "mantle",
            type: "mantle",
            decimals: 18,
            reference: "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0000"
        )
        let duplicateLegacy = TokenRecord(
            coinUid: "usd-coin",
            blockchainUid: "blast",
            type: "blast",
            decimals: 6,
            reference: "0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"
        )
        let duplicateEip20 = TokenRecord(
            coinUid: "usd-coin",
            blockchainUid: "blast",
            type: "eip20",
            decimals: 6,
            reference: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        )
        let unicodeNumeralContract = TokenRecord(
            coinUid: "unsafe-unicode",
            blockchainUid: "blast",
            type: "blast",
            decimals: 18,
            reference: "0x" + String(repeating: "١", count: 40)
        )

        let result = ThwalletEvmNetworkCatalog.normalize(
            coins: [Coin(uid: "usd-coin", name: "USD Coin", code: "USDC")],
            blockchainRecords: [],
            tokenRecords: [validContract, unsafeContract, mantlePseudoNative, duplicateLegacy, duplicateEip20, unicodeNumeralContract]
        )

        XCTAssertEqual(result.blockchainRecords.map(\.uid), ["cronos", "blast", "mantle", "sei-network", "hyperevm", "robinhood"])
        XCTAssertEqual(Set(result.coins.map(\.uid)).count, result.coins.count)
        XCTAssertEqual(result.coins.filter { $0.uid == "ethereum" }.count, 1)
        XCTAssertEqual(result.tokenRecords.filter { $0.type == "native" }.count, 6)
        XCTAssertFalse(result.tokenRecords.contains { $0.coinUid == "tether" })
        XCTAssertFalse(result.tokenRecords.contains { $0.coinUid == "unsafe-unicode" })
        XCTAssertEqual(
            result.tokenRecords.first { $0.coinUid == "usd-coin" }?.reference,
            "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        )
        XCTAssertFalse(result.tokenRecords.contains { $0.reference == "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0000" })

        let canonicalContracts = result.tokenRecords.filter {
            $0.blockchainUid == "blast" && $0.reference == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        }
        XCTAssertEqual(canonicalContracts.count, 1)
        XCTAssertEqual(canonicalContracts.first?.type, "eip20")

        let query = TokenQuery(
            blockchainType: BlockchainType(uid: "blast"),
            tokenType: .eip20(address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        )
        XCTAssertEqual(query.id, "blast|eip20:0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertEqual(TokenQuery(id: query.id), query)

        try withTemporaryStorage { storage in
            try storage.update(
                coins: result.coins,
                blockchainRecords: result.blockchainRecords,
                tokenRecords: result.tokenRecords
            )

            let persisted = try XCTUnwrap(storage.tokenInfoRecord(query: query)?.token)
            XCTAssertEqual(persisted.tokenQuery, query)
            XCTAssertEqual(persisted.decimals, 6)
        }
    }

    func testDropsEveryCandidateWhenCanonicalContractMetadataConflicts() {
        let address = "0x1111111111111111111111111111111111111111"
        let cases: [[TokenRecord]] = [
            [
                TokenRecord(coinUid: "coin-a", blockchainUid: "blast", type: "blast", decimals: 6, reference: address.uppercased()),
                TokenRecord(coinUid: "coin-b", blockchainUid: "blast", type: "eip20", decimals: 6, reference: address),
            ],
            [
                TokenRecord(coinUid: "coin-a", blockchainUid: "blast", type: "blast", decimals: 6, reference: address.uppercased()),
                TokenRecord(coinUid: "coin-a", blockchainUid: "blast", type: "eip20", decimals: 18, reference: address),
            ],
        ]

        for tokenRecords in cases {
            let result = ThwalletEvmNetworkCatalog.normalize(
                coins: [],
                blockchainRecords: [],
                tokenRecords: tokenRecords
            )

            XCTAssertFalse(
                result.tokenRecords.contains { $0.blockchainUid == "blast" && $0.reference == address },
                "Ambiguous metadata must drop every row for the canonical TokenQuery"
            )
        }
    }

    func testDropsAlreadyCanonicalEip20WithZeroDecimals() {
        let result = ThwalletEvmNetworkCatalog.normalize(
            coins: [],
            blockchainRecords: [],
            tokenRecords: [
                TokenRecord(
                    coinUid: "zero-decimal-token",
                    blockchainUid: "cronos",
                    type: "eip20",
                    decimals: 0,
                    reference: "0x2222222222222222222222222222222222222222"
                ),
            ]
        )

        XCTAssertFalse(result.tokenRecords.contains { $0.coinUid == "zero-decimal-token" })
    }

    func testDropsMantlePseudoNativeWhenAlreadyTypedEip20() {
        let pseudoNative = "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0000"
        let result = ThwalletEvmNetworkCatalog.normalize(
            coins: [],
            blockchainRecords: [],
            tokenRecords: [
                TokenRecord(
                    coinUid: "mantle",
                    blockchainUid: "mantle",
                    type: "eip20",
                    decimals: 18,
                    reference: pseudoNative
                ),
            ]
        )

        XCTAssertFalse(result.tokenRecords.contains { $0.reference == pseudoNative })
        XCTAssertEqual(result.tokenRecords.filter { $0.blockchainUid == "mantle" && $0.type == "native" }.count, 1)
    }

    func testNormalizationIsIdempotentAndKeepsExactlyOneNativePerManagedNetwork() {
        let contractAddress = "0x3333333333333333333333333333333333333333"
        let first = ThwalletEvmNetworkCatalog.normalize(
            coins: [Coin(uid: "usd-coin", name: "USD Coin", code: "USDC")],
            blockchainRecords: [
                BlockchainRecord(uid: "blast", name: "Stale Blast", explorerUrl: nil),
                BlockchainRecord(uid: "bitcoin", name: "Bitcoin", explorerUrl: nil),
            ],
            tokenRecords: [
                TokenRecord(coinUid: "ethereum", blockchainUid: "blast", type: "native", decimals: 9),
                TokenRecord(coinUid: "ethereum", blockchainUid: "blast", type: "blast", decimals: 18),
                TokenRecord(coinUid: "usd-coin", blockchainUid: "blast", type: "blast", decimals: 6, reference: contractAddress),
                TokenRecord(coinUid: "bitcoin", blockchainUid: "bitcoin", type: "native", decimals: 8),
            ]
        )
        let second = ThwalletEvmNetworkCatalog.normalize(
            coins: first.coins,
            blockchainRecords: first.blockchainRecords,
            tokenRecords: first.tokenRecords
        )

        XCTAssertEqual(snapshot(first), snapshot(second))

        for network in ThwalletEvmNetworkCatalog.networks {
            let nativeRows = second.tokenRecords.filter {
                $0.blockchainUid == network.blockchainUid && $0.type == "native"
            }
            XCTAssertEqual(nativeRows.count, 1, "Expected one native row for \(network.blockchainUid)")
            XCTAssertEqual(nativeRows.first?.coinUid, network.nativeCoin.uid)
            XCTAssertEqual(nativeRows.first?.decimals, 18)
            XCTAssertNil(nativeRows.first?.reference)
        }
    }

    private func snapshot(_ data: ThwalletEvmNetworkCatalog.NormalizedData) -> [String] {
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

func withTemporaryStorage(_ body: (CoinStorage) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pool = try DatabasePool(path: directory.appendingPathComponent("market-kit.sqlite").path)
    try body(CoinStorage(dbPool: pool))
}
