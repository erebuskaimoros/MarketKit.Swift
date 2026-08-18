enum ThwalletXrpCatalog {
    private static let blockchainUid = "ripple"
    private static let nativeCoin = Coin(
        uid: "ripple",
        name: "XRP",
        code: "XRP",
        coinGeckoId: "ripple"
    )

    struct NormalizedData {
        let coins: [Coin]
        let blockchainRecords: [BlockchainRecord]
        let tokenRecords: [TokenRecord]
    }

    static func normalize(
        coins: [Coin],
        blockchainRecords: [BlockchainRecord],
        tokenRecords: [TokenRecord]
    ) -> NormalizedData {
        var normalizedCoins = coins.filter { $0.uid != nativeCoin.uid }
        if let existing = coins.first(where: { $0.uid == nativeCoin.uid }) {
            normalizedCoins.append(
                Coin(
                    uid: nativeCoin.uid,
                    name: nativeCoin.name,
                    code: nativeCoin.code,
                    marketCapRank: existing.marketCapRank,
                    coinGeckoId: existing.coinGeckoId ?? nativeCoin.coinGeckoId,
                    image: existing.image
                )
            )
        } else {
            normalizedCoins.append(nativeCoin)
        }

        var normalizedBlockchains = blockchainRecords.filter { $0.uid != blockchainUid }
        normalizedBlockchains.append(
            BlockchainRecord(
                uid: blockchainUid,
                name: "XRP Ledger",
                explorerUrl: "https://xrpscan.com/account/$ref"
            )
        )

        var normalizedTokens = tokenRecords.filter { $0.blockchainUid != blockchainUid }
        normalizedTokens.append(
            TokenRecord(
                coinUid: nativeCoin.uid,
                blockchainUid: blockchainUid,
                type: "native",
                decimals: 6
            )
        )

        return NormalizedData(
            coins: normalizedCoins,
            blockchainRecords: normalizedBlockchains,
            tokenRecords: normalizedTokens
        )
    }
}
