import Foundation

/// Államkincstár export-fájljából készít portfólió sorokat.
enum StateTreasuryImporter {

    enum ImportError: LocalizedError {
        case unreadable
        case noHeader
        case noPositions

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "Az állományt nem sikerült beolvasni."
            case .noHeader:
                "Nem található az Államkincstár export formátumhoz illő fejléc."
            case .noPositions:
                "Az export nem tartalmaz felismerhető állampapír sort."
            }
        }
    }

    struct Position {
        var name: String
        var currentValueHUF: Decimal
        var investedValueHUF: Decimal?
        var isin: String?
        var nominalValue: Decimal?
        var maturityDate: Date?
        var couponPct: Decimal?
    }

    struct Result {
        var account: String
        var platformID: String
        var accountName: String
        var asset: CashAsset
        var positions: Int
        var positionDetails: [StateTreasuryPosition]
        var warnings: [String]
    }

    private enum Column: Int {
        case name, currentValue, investedValue, isin, nominalValue, maturityDate, couponPct
    }

    /// Gyors felismerés a tartalomból, még a fájlnév nélkül.
    static func detect(text: String) -> Bool {
        let lower = text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let keywords = [
            "allamkincstar", "allampapir", "mak", "pmap", "bmap", "maap", "dkj",
            "zlap", "ikap", "kincstar", "allami"
        ]
        return keywords.contains { lower.contains($0) }
    }

    static func `import`(text: String, accountHint: String) throws -> Result {
        let normalizedLines = text.split(whereSeparator: \.isNewline).map {
            String($0).withoutUTF8BOM.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard normalizedLines.count >= 2 else { throw ImportError.unreadable }

        let delimiter = preferredDelimiter(in: normalizedLines)
        let rows = normalizedLines.map { parse(line: String($0), by: delimiter) }
        guard let headerIndex = rows.firstIndex(where: { mapColumns($0).contains { $0 != nil } })
        else { throw ImportError.noHeader }

        let header = mapColumns(rows[headerIndex])
        let data = rows[(headerIndex + 1)...]
        var positions: [Position] = []
        var unknownRows = 0

        for row in data {
            guard !row.isEmpty else { continue }
            func value(_ column: Column) -> String? {
                guard let idx = header.firstIndex(of: column), idx < row.count else { return nil }
                let raw = row[idx].trimmingCharacters(in: .whitespaces)
                return raw.isEmpty ? nil : raw
            }

            guard let current = parseAmount(value: value(.currentValue))
            else { unknownRows += 1; continue }
            let name = parseName(row: row, header: header)
            let invested = parseAmount(value: value(.investedValue))
            let isin = value(.isin).map(normalizeISIN)
            let nominal = parseAmount(value: value(.nominalValue))
            let maturity = parseDate(value: value(.maturityDate))
            let coupon = parseAmount(value: value(.couponPct))

            positions.append(Position(name: name, currentValueHUF: current,
                                      investedValueHUF: invested, isin: isin,
                                      nominalValue: nominal, maturityDate: maturity,
                                      couponPct: coupon))
        }

        guard !positions.isEmpty else { throw ImportError.noPositions }

        let totalCurrent = positions.reduce(Decimal(0)) { $0 + $1.currentValueHUF }
        let asOf = parseAsOfDate(text)
        let accountName = inferAccountName(from: text, fallback: accountHint)
        let accountID = inferAccountID(from: accountHint, text: text)
        let positionDetails = positions.map { position in
            StateTreasuryPosition(
                id: stableID(for: position),
                name: position.name,
                isin: position.isin,
                nominalValue: position.nominalValue,
                currentValueHUF: position.currentValueHUF,
                investedValueHUF: position.investedValueHUF,
                maturityDate: position.maturityDate,
                couponPct: position.couponPct,
                asOf: asOf
            )
        }

        var warnings: [String] = []
        if unknownRows > 0 {
            warnings.append("\(unknownRows) sorat nem sikerült feldolgozni a táblázatból.")
        }
        if positions.count == 1 {
            warnings.append("Egy befektetés található az exportból.")
        }

        let asset = CashAsset(
            platform: accountID,
            name: accountName,
            balance: totalCurrent,
            currency: "HUF",
            asOf: asOf
        )
        return Result(
            account: accountID,
            platformID: accountID,
            accountName: accountName,
            asset: asset,
            positions: positions.count,
            positionDetails: positionDetails,
            warnings: warnings
        )
    }

    // MARK: - Sor- és fejlécfeldolgozás

    private static func parse(line: String, by delimiter: Character) -> [String] {
        // The shared parser handles quoted delimiters for comma, semicolon,
        // tab and pipe exports alike.
        return StatementImporter.parse(line: line, delimiter: delimiter)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func preferredDelimiter(in lines: [String]) -> Character {
        let candidates: [Character] = [";", "\t", "|", ","]
        let sample = lines.prefix(8)
        var scores: [Character: Int] = [";": 0, "\t": 0, "|": 0, ",": 0]
        for line in sample {
            for delim in candidates {
                let hits = line.filter { $0 == delim }.count
                if hits > 0 { scores[delim, default: 0] += hits }
            }
        }
        let best = candidates.max { scores[$0, default: 0] < scores[$1, default: 0] }
        return best ?? ","
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private static func mapColumns(_ row: [String]) -> [Column?] {
        row.map { field in
            let v = normalize(field)
            if contains(v, any: ["megnevez", "termek", "ertekpapir", "kepviselo", "instrument", "name"]) {
                return .name
            }
            // A „Befizetés értéke” mezőben is szerepel az „érték”, ezért az
            // eredeti/bekerülési jelzőket mindig a piaci érték előtt nézzük.
            if contains(v, any: ["beszerzes", "bekerul", "vasarlas", "befizetes", "beadas", "eredeti", "invested", "cost"]) {
                return .investedValue
            }
            if contains(v, any: ["isin", "valor", "azonosito"]) {
                return .isin
            }
            if contains(v, any: ["nev ertek", "nevertek", "nominal", "darab", "mennyiseg", "quantity", "db"]) {
                return .nominalValue
            }
            if contains(v, any: ["lejar", "esedek", "maturity", "due date"]) {
                return .maturityDate
            }
            if contains(v, any: ["kamat", "hozam", "coupon", "interest rate"]) {
                return .couponPct
            }
            if contains(v, any: ["jelen", "aktual", "piaci", "brutto", "egyseges", "current", "market", "ertek"]) {
                return .currentValue
            }
            return nil
        }
    }

    private static func contains(_ text: String, any patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    private static func parseAmount(value: String?) -> Decimal? {
        guard let raw = value else { return nil }
        return HungarianCSV.number(raw
            .replacingOccurrences(of: "HUF", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    private static func parseDate(value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return parseAsOfDate(value)
    }

    private static func normalizeISIN(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func stableID(for position: Position) -> String {
        if let isin = position.isin, !isin.isEmpty { return "isin:\(isin)" }
        return "name:\(normalize(position.name))"
    }

    private static func parseName(row: [String], header: [Column?]) -> String {
        if let idx = header.firstIndex(of: .name), idx < row.count {
            let raw = row[idx].trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty { return raw }
        }
        return "Állampapír"
    }

    private static func parseAsOfDate(_ text: String) -> Date? {
        let patterns: [(String, String)] = [
            (#"\d{4}\.\d{2}\.\d{2}\."#, "yyyy.MM.dd."),
            (#"\d{4}\.\d{2}\.\d{2}"#, "yyyy.MM.dd"),
            (#"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#, "yyyy-MM-dd HH:mm:ss"),
            (#"\d{4}-\d{2}-\d{2}"#, "yyyy-MM-dd"),
            (#"\d{4}/\d{2}/\d{2}"#, "yyyy/MM/dd"),
            (#"\d{2}\.\d{2}\.\d{4}"#, "dd.MM.yyyy"),
            (#"\d{2}/\d{2}/\d{4}"#, "dd/MM/yyyy")
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        for (pattern, format) in patterns {
            if let found = firstMatch(pattern, in: text) {
                formatter.dateFormat = format
                if let date = formatter.date(from: found) { return date }
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, range: range) {
            return String(text[Range(match.range, in: text)!])
        }
        return nil
    }

    private static func inferAccountID(from hint: String, text: String) -> String {
        // Az export neve exportonként változhat (akár dátumot is tartalmazhat),
        // de ugyanazt az Államkincstár-számlát szeretnénk frissíteni.
        let normalized = normalize(text)
        if normalized.contains("allamkincstar") || normalized.contains("kincstar") {
            return "treasury-allamkincstar"
        }
        let slug = hint
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "-")
        let cleaned = slug.replacingOccurrences(of: "[^a-zA-Z0-9-]", with: "", options: .regularExpression)
        return "treasury-" + (cleaned.isEmpty ? String(UUID().uuidString.lowercased().prefix(8)) : String(cleaned))
    }

    private static func inferAccountName(from text: String, fallback: String) -> String {
        let normalized = normalize(text)
        if normalized.contains("allampapir") && normalized.contains("tervezet") {
            return "Államkincstár export"
        }
        if let line = text.split(whereSeparator: \.isNewline).first(where: { $0.contains(":") }),
           line.contains("Fiók") || line.contains("Profil") || line.contains("Portfólió") {
            return String(line.split(separator: ":").last ?? Substring(fallback)).trimmingCharacters(in: .whitespaces)
        }
        return fallback.isEmpty ? "Államkincstár portfólió" : fallback
    }
}
