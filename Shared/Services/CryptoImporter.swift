import Foundation

/// Gyakori kripto/wallet exportok helyi, csak olvasható beolvasója.
///
/// Szándékosan nem kapcsolódik tőzsdéhez és nem kezel privát kulcsot. Az
/// exportban szereplő HUF érték a mérés; élő árfolyam nélkül nem találunk ki
/// új árat, és az import nem indít tranzakciót.
enum CryptoImporter {

    enum ImportError: LocalizedError {
        case unreadable, noHeader, noPositions, unsupportedCurrency

        var errorDescription: String? {
            switch self {
            case .unreadable: "A kripto-exportot nem sikerült beolvasni."
            case .noHeader: "Nem található eszköz- és értékoszlop a kripto-exportban."
            case .noPositions: "Az exportban nincs felismerhető kripto-pozíció."
            case .unsupportedCurrency: "A kripto-export értéke nem HUF-ban szerepel; biztonságos átváltási ár nélkül nem importáltuk."
            }
        }
    }

    struct Position {
        var symbol: String
        var name: String
        var quantity: Decimal?
        var valueHUF: Decimal
        var investedHUF: Decimal?
        var unitPriceHUF: Decimal?
        var asOf: Date?
    }

    struct Result {
        var account: String
        var accountName: String
        var positions: [CryptoPosition]
        var warnings: [String]
    }

    private enum Column: Int {
        case symbol, name, quantity, value, invested, unitPrice, currency, date
    }

    static func detect(text: String, fileName: String = "") -> Bool {
        let normalized = normalize("\(fileName) \(text)")
        let cryptoWords = [
            "crypto", "kripto", "bitcoin", "ethereum", "btc", "eth", "wallet",
            "binance", "coinbase", "kraken", "bitpanda", "ledger", "metamask", "token"
        ]
        guard cryptoWords.contains(where: { normalized.contains($0) }) else { return false }
        let hasAsset = normalized.contains("symbol") || normalized.contains("coin")
            || normalized.contains("asset") || normalized.contains("token")
        let hasValue = normalized.contains("value") || normalized.contains("ertek")
            || normalized.contains("balance") || normalized.contains("egyenleg")
        return hasAsset && hasValue
    }

    static func `import`(text: String, accountHint: String) throws -> Result {
        let lines = text.split(whereSeparator: \.isNewline).map {
            String($0).withoutUTF8BOM.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { throw ImportError.unreadable }

        let delimiter = preferredDelimiter(in: lines)
        let rows = lines.map { StatementImporter.parse(line: $0, delimiter: delimiter) }
        guard let headerIndex = rows.firstIndex(where: { columns(for: $0).contains { $0 == .symbol } && columns(for: $0).contains { $0 == .value } })
        else { throw ImportError.noHeader }
        let header = columns(for: rows[headerIndex])
        var parsed: [Position] = []
        var skipped = 0
        var unsupported = 0

        for row in rows.dropFirst(headerIndex + 1) {
            guard !row.isEmpty else { continue }
            func value(_ column: Column) -> String? {
                guard let index = header.firstIndex(of: column), index < row.count else { return nil }
                let raw = row[index].trimmingCharacters(in: .whitespaces)
                return raw.isEmpty ? nil : raw
            }

            guard let rawSymbol = value(.symbol) else { skipped += 1; continue }
            let symbol = rawSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let name = value(.name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? symbol
            if isSummaryRow(symbol: symbol, name: name) { continue }

            let currency = value(.currency)?.uppercased() ?? "HUF"
            guard currency == "HUF" || currency == "FT" || currency == "FORINT" else {
                unsupported += 1
                continue
            }
            var current = parseAmount(value(.value)) ?? 0
            let quantity = parseAmount(value(.quantity))
            let unitPrice = parseAmount(value(.unitPrice))
            if current == 0, let quantity, let unitPrice {
                current = quantity * unitPrice
            }
            guard current > 0 else { skipped += 1; continue }
            let invested = parseAmount(value(.invested))
            parsed.append(Position(symbol: symbol, name: name, quantity: quantity,
                                   valueHUF: current, investedHUF: invested,
                                   unitPriceHUF: unitPrice, asOf: parseDate(value(.date))))
        }
        guard !parsed.isEmpty else {
            if unsupported > 0 { throw ImportError.unsupportedCurrency }
            throw ImportError.noPositions
        }

        let account = inferAccountID(from: accountHint, text: text)
        let accountName = inferAccountName(from: accountHint, text: text)
        var seen: [String: Int] = [:]
        let positions = parsed.map { item in
            let base = "\(account):\(item.symbol)"
            let index = seen[item.symbol, default: 0]
            seen[item.symbol] = index + 1
            let id = index == 0 ? base : "\(base):\(index)"
            return CryptoPosition(id: id, platform: account, symbol: item.symbol,
                                  name: item.name, quantity: item.quantity,
                                  currentValueHUF: item.valueHUF,
                                  investedValueHUF: item.investedHUF,
                                  unitPriceHUF: item.unitPriceHUF,
                                  asOf: item.asOf, source: accountName)
        }
        var warnings = [
            "Csak olvasható import: az exportált HUF értéket mentettük, élő árfolyamot nem kérünk."
        ]
        if skipped > 0 { warnings.append("\(skipped) sor nem volt teljesen értelmezhető.") }
        if unsupported > 0 { warnings.append("\(unsupported) nem HUF értékű sor kimaradt; biztonságos árfolyam nélkül nem váltjuk át.") }
        return Result(account: account, accountName: accountName,
                      positions: positions, warnings: warnings)
    }

    private static func columns(for row: [String]) -> [Column?] {
        row.map { field in
            let v = normalize(field)
            if contains(v, any: ["asset name", "coin name", "megnevez", "name"]) { return .name }
            if contains(v, any: ["symbol", "ticker", "coin", "token", "asset"]) { return .symbol }
            if contains(v, any: ["currency", "deviza", "ccy"]) { return .currency }
            if contains(v, any: ["date", "datum", "as of", "snapshot"]) { return .date }
            if contains(v, any: ["cost", "invested", "bekerul", "befizet"]) { return .invested }
            if contains(v, any: ["unit price", "price", "ar", "árfolyam"]) { return .unitPrice }
            if contains(v, any: ["current value", "market value", "total value", "value", "ertek", "egyenleg", "worth"]) { return .value }
            if contains(v, any: ["quantity", "amount", "balance", "units", "holdings", "mennyiseg", "darab"]) { return .quantity }
            return nil
        }
    }

    private static func contains(_ text: String, any patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    private static func parseAmount(_ raw: String?) -> Decimal? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "HUF", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Ft", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "₣", with: "")
            .trimmingCharacters(in: .whitespaces)
        return HungarianCSV.number(cleaned)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let patterns: [(String, String)] = [
            (#"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#, "yyyy-MM-dd HH:mm:ss"),
            (#"\d{4}-\d{2}-\d{2}"#, "yyyy-MM-dd"),
            (#"\d{4}\.\d{2}\.\d{2}\."#, "yyyy.MM.dd."),
            (#"\d{2}\.\d{2}\.\d{4}"#, "dd.MM.yyyy")
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        for (pattern, format) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw)),
                  let range = Range(match.range, in: raw) else { continue }
            formatter.dateFormat = format
            if let date = formatter.date(from: String(raw[range])) { return date }
        }
        return nil
    }

    private static func isSummaryRow(symbol: String, name: String) -> Bool {
        let normalized = normalize("\(symbol) \(name)")
        return ["total", "osszesen", "mindosszesen", "subtotal", "cash", "fiat"].contains {
            normalized == $0 || normalized.hasPrefix("\($0) ")
        }
    }

    private static func preferredDelimiter(in lines: [String]) -> Character {
        let candidates: [Character] = [";", "\t", "|", ","]
        let sample = lines.prefix(8)
        var scores: [Character: Int] = [";": 0, "\t": 0, "|": 0, ",": 0]
        for line in sample {
            for delimiter in candidates {
                scores[delimiter, default: 0] += line.filter { $0 == delimiter }.count
            }
        }
        return candidates.max { scores[$0, default: 0] < scores[$1, default: 0] } ?? ";"
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func inferAccountID(from hint: String, text: String) -> String {
        let normalized = normalize("\(hint) \(text)")
        let known: [(String, String)] = [
            ("binance", "binance"), ("coinbase", "coinbase"), ("kraken", "kraken"),
            ("bitpanda", "bitpanda"), ("ledger", "ledger"), ("metamask", "metamask")
        ]
        if let match = known.first(where: { normalized.contains($0.0) }) { return "crypto-\(match.1)" }
        return "crypto-wallet"
    }

    private static func inferAccountName(from hint: String, text: String) -> String {
        let normalized = normalize("\(hint) \(text)")
        let names: [(String, String)] = [
            ("binance", "Binance"), ("coinbase", "Coinbase"), ("kraken", "Kraken"),
            ("bitpanda", "Bitpanda"), ("ledger", "Ledger wallet"), ("metamask", "MetaMask")
        ]
        return names.first(where: { normalized.contains($0.0) })?.1 ?? "Kripto wallet"
    }
}
