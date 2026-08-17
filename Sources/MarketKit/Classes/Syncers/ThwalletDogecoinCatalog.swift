enum ThwalletDogecoinCatalog {
    private static let blockchainUid = "dogecoin"
    private static let nativeCoin = Coin(
        uid: "dogecoin",
        name: "Dogecoin",
        code: "DOGE",
        coinGeckoId: "dogecoin"
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
        var normalizedCoins = coins
        if let index = normalizedCoins.firstIndex(where: { $0.uid == nativeCoin.uid }) {
            let existing = normalizedCoins[index]
            normalizedCoins[index] = Coin(
                uid: nativeCoin.uid,
                name: nativeCoin.name,
                code: nativeCoin.code,
                marketCapRank: existing.marketCapRank,
                coinGeckoId: existing.coinGeckoId ?? nativeCoin.coinGeckoId,
                image: existing.image
            )
        } else {
            normalizedCoins.append(nativeCoin)
        }

        var normalizedBlockchains = blockchainRecords.filter { $0.uid != blockchainUid }
        normalizedBlockchains.append(
            BlockchainRecord(
                uid: blockchainUid,
                name: "Dogecoin",
                explorerUrl: "https://blockchair.com/dogecoin/address/$ref"
            )
        )

        var normalizedTokens = tokenRecords.filter { $0.blockchainUid != blockchainUid }
        normalizedTokens.append(
            TokenRecord(
                coinUid: nativeCoin.uid,
                blockchainUid: blockchainUid,
                type: "native",
                decimals: 8
            )
        )

        return NormalizedData(
            coins: normalizedCoins,
            blockchainRecords: normalizedBlockchains,
            tokenRecords: normalizedTokens
        )
    }
}
