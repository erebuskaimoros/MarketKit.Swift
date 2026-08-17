import Foundation

/// Normalizes the six EVM networks enabled by Thwallet at the MarketKit storage boundary.
///
/// The market API historically represented these networks as unsupported per-chain token types,
/// often without a contract address or decimals. Wallet code must never infer a spendable EIP-20
/// token from incomplete metadata, so this transform drops unsafe rows, canonicalizes complete
/// contracts, and supplies authoritative native-token rows after every dump or API refresh.
enum ThwalletEvmNetworkCatalog {
    private static let mantleNativePseudoAddress = "0xdeaddeaddeaddeaddeaddeaddeaddeaddead0000"
    private static let lowercaseEvmAddressCharacters = Set("0123456789abcdef")

    struct Network {
        let blockchainUid: String
        let blockchainName: String
        let explorerUrl: String
        let nativeCoin: Coin
    }

    struct NormalizedData {
        let coins: [Coin]
        let blockchainRecords: [BlockchainRecord]
        let tokenRecords: [TokenRecord]
    }

    static let networks: [Network] = [
        Network(
            blockchainUid: "cronos",
            blockchainName: "Cronos",
            explorerUrl: "https://explorer.cronos.com/address/$ref",
            nativeCoin: Coin(uid: "crypto-com-chain", name: "Cronos", code: "CRO", coinGeckoId: "crypto-com-chain")
        ),
        Network(
            blockchainUid: "blast",
            blockchainName: "Blast",
            explorerUrl: "https://blastscan.io/address/$ref",
            nativeCoin: Coin(uid: "ethereum", name: "Ethereum", code: "ETH", coinGeckoId: "ethereum")
        ),
        Network(
            blockchainUid: "mantle",
            blockchainName: "Mantle",
            explorerUrl: "https://mantlescan.xyz/address/$ref",
            nativeCoin: Coin(uid: "mantle", name: "Mantle", code: "MNT", coinGeckoId: "mantle")
        ),
        Network(
            blockchainUid: "sei-network",
            blockchainName: "Sei EVM",
            explorerUrl: "https://seiscan.io/address/$ref",
            nativeCoin: Coin(uid: "sei-network", name: "Sei", code: "SEI", coinGeckoId: "sei-network")
        ),
        Network(
            blockchainUid: "hyperevm",
            blockchainName: "HyperEVM",
            explorerUrl: "https://hyperevmscan.io/address/$ref",
            nativeCoin: Coin(uid: "hyperliquid", name: "Hyperliquid", code: "HYPE", coinGeckoId: "hyperliquid")
        ),
        Network(
            blockchainUid: "robinhood",
            blockchainName: "Robinhood Chain",
            explorerUrl: "https://robinhoodchain.blockscout.com/address/$ref",
            nativeCoin: Coin(uid: "ethereum", name: "Ethereum", code: "ETH", coinGeckoId: "ethereum")
        ),
    ]

    private static let networkByUid = Dictionary(uniqueKeysWithValues: networks.map { ($0.blockchainUid, $0) })

    static func normalize(coins: [Coin], blockchainRecords: [BlockchainRecord], tokenRecords: [TokenRecord]) -> NormalizedData {
        var normalizedCoins = coins
        var existingCoinUids = Set(coins.map(\.uid))
        for network in networks where existingCoinUids.insert(network.nativeCoin.uid).inserted {
            normalizedCoins.append(network.nativeCoin)
        }

        let networkUids = Set(networks.map(\.blockchainUid))
        var normalizedBlockchains = blockchainRecords.filter { !networkUids.contains($0.uid) }
        normalizedBlockchains.append(contentsOf: networks.map {
            BlockchainRecord(uid: $0.blockchainUid, name: $0.blockchainName, explorerUrl: $0.explorerUrl)
        })

        var normalizedTokens = deduplicateManagedTokens(tokenRecords.compactMap(normalize(tokenRecord:)))
        normalizedTokens.append(contentsOf: networks.map {
            TokenRecord(
                coinUid: $0.nativeCoin.uid,
                blockchainUid: $0.blockchainUid,
                type: "native",
                decimals: 18
            )
        })

        return NormalizedData(
            coins: normalizedCoins,
            blockchainRecords: normalizedBlockchains,
            tokenRecords: normalizedTokens
        )
    }

    private static func deduplicateManagedTokens(_ tokenRecords: [TokenRecord]) -> [TokenRecord] {
        var unmanaged = [TokenRecord]()
        var managedByQuery = [String: [TokenRecord]]()

        for tokenRecord in tokenRecords {
            guard networkByUid[tokenRecord.blockchainUid] != nil else {
                unmanaged.append(tokenRecord)
                continue
            }

            let query = TokenQuery(
                blockchainType: BlockchainType(uid: tokenRecord.blockchainUid),
                tokenType: TokenType(type: tokenRecord.type, reference: tokenRecord.reference)
            )
            managedByQuery[query.id, default: []].append(tokenRecord)
        }

        let managed = managedByQuery.keys.sorted().compactMap { queryId -> TokenRecord? in
            guard let candidates = managedByQuery[queryId] else {
                return nil
            }

            // Identical legacy and EIP-20 rows safely collapse to one canonical TokenQuery.
            // Conflicting coin identity or decimals are ambiguous and remain unavailable rather
            // than selecting a potentially unsafe transfer scale based on API ordering.
            let metadata = Set(candidates.map { candidate in
                "\(candidate.coinUid)|\(candidate.decimals.map { String($0) } ?? "nil")"
            })
            guard metadata.count == 1 else {
                return nil
            }

            return candidates.sorted {
                let lhs = "\($0.coinUid)|\($0.type)|\($0.reference ?? "")"
                let rhs = "\($1.coinUid)|\($1.type)|\($1.reference ?? "")"
                return lhs < rhs
            }.first
        }

        return unmanaged + managed
    }

    private static func normalize(tokenRecord: TokenRecord) -> TokenRecord? {
        guard let network = networkByUid[tokenRecord.blockchainUid] else {
            return tokenRecord
        }

        let reference = tokenRecord.reference?.lowercased()
        let isNativeCandidate = tokenRecord.coinUid == network.nativeCoin.uid && (
            tokenRecord.type == "native" ||
                (tokenRecord.type == network.blockchainUid && (reference == nil || reference?.isEmpty == true)) ||
                (network.blockchainUid == "mantle" && reference == mantleNativePseudoAddress)
        )
        if isNativeCandidate {
            // Replaced by the single authoritative native row appended by `normalize`.
            return nil
        }

        guard let reference, isEvmAddress(reference), let decimals = tokenRecord.decimals, decimals > 0 else {
            // Missing address or decimals is unsafe: exposing it could scale or route a transfer
            // incorrectly. It can still be added manually after on-chain metadata validation.
            return nil
        }

        if network.blockchainUid == "mantle", reference == mantleNativePseudoAddress {
            return nil
        }

        return TokenRecord(
            coinUid: tokenRecord.coinUid,
            blockchainUid: tokenRecord.blockchainUid,
            type: "eip20",
            decimals: decimals,
            reference: reference
        )
    }

    private static func isEvmAddress(_ value: String) -> Bool {
        guard value.count == 42, value.hasPrefix("0x") else {
            return false
        }

        return value.dropFirst(2).allSatisfy(lowercaseEvmAddressCharacters.contains)
    }
}
