import Foundation

/// OTP bankszámla- és hitelkártya-kivonat beolvasása (PDF szövegrétegéből).
///
/// Két különböző elrendezés, ezért két elemző:
///
/// **Bankszámla** — a tétel KÉT sor: az elsőn a könyvelési nap, az értéknap és
/// az összeg, a másodikon a megnevezés. Az egyenlegsoroknál csak egy dátum van.
/// ```
/// 26.07.02 249.072
/// NYITÓ EGYENLEG
/// 26.07.03 26.07.03 -3.790
/// VÁSÁRLÁS KÁRTYÁVAL, …
/// ```
///
/// **Hitelkártya** — a tétel EGY sor, az összeg a végén:
/// ```
/// 26.08.05 26.08.05 VÁSÁRLÁS KÁRTYÁVAL, …, Kártyagyártási díj -3.673
/// ```
///
/// Az összegek forintosak, ezres PONTTAL és tizedes nélkül (`-1.505.050`).
/// Ezt nem a `HungarianCSV`-re bízzuk: ott a „pont + két számjegy" tizedesnek
/// számít, ami itt sosem fordul elő, de egy jövőbeli devizás soron elrontaná.
enum OTPImporter {

    enum Kind { case account, credit }

    struct Entry {
        var date: Date
        var valueDate: Date
        var text: String
        var amountHUF: Decimal
    }

    struct Result {
        var kind: Kind
        var accountNumber: String
        var currency: String
        var opening: Decimal
        var closing: Decimal
        var entries: [Entry]
        /// A kivonat SAJÁT összesítése — ehhez mérjük a beolvasást.
        var statedCredits: Decimal?
        var statedDebits: Decimal?
        /// Csak hitelkártyánál.
        var totalDebt: Decimal?
        var minimumPayment: Decimal?
        var dueDate: Date?
        var creditLimit: Decimal?
        var warnings: [String] = []

        /// Napi záróegyenleg a nyitóból és a tételekből — ebből épül a görbe.
        var dailyBalances: [Date: Decimal] {
            var running = opening
            var byDay: [Date: Decimal] = [:]
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                running += entry.amountHUF
                byDay[entry.date] = running
            }
            return byDay
        }
    }

    // MARK: - Felismerés

    static func detect(text: String) -> Kind? {
        guard text.contains("OTP BANK NYRT") else { return nil }
        if text.contains("Hitelkártya számlakivonat") { return .credit }
        if text.contains("SZÁMLAKIVONAT"), text.contains("FORGALMAK") { return .account }
        return nil
    }

    // MARK: - Közös elemek

    /// „26.07.02" → dátum. Kétjegyű év: 2000 + YY. Ezek a kivonatok 2000 után
    /// keletkeztek, más értelmezés nem merül fel.
    static func date(_ text: String) -> Date? {
        let parts = text.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        return calendar.date(from: DateComponents(year: 2000 + year, month: month, day: day))
    }

    /// „-1.505.050" → −1505050. Forintos egész, ezres pontokkal.
    static func amount(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard !cleaned.isEmpty, cleaned.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func value(after label: String, in text: String) -> Decimal? {
        guard let line = text.split(whereSeparator: \.isNewline)
            .first(where: { $0.contains(label) }) else { return nil }
        guard let raw = firstMatch("-?[0-9][0-9.]*", in: String(line.dropFirst(
            line.range(of: label)!.upperBound.utf16Offset(in: line))))
        else { return nil }
        return amount(raw)
    }

    // MARK: - Beolvasás

    static func `import`(text: String) throws -> Result {
        guard let kind = detect(text: text) else { throw ImportError.unknownFormat }
        return switch kind {
        case .account: try importAccount(text: text)
        case .credit:  try importCredit(text: text)
        }
    }

    enum ImportError: LocalizedError {
        case unknownFormat, noEntries
        var errorDescription: String? {
            switch self {
            case .unknownFormat: "Ez nem OTP számlakivonat."
            case .noEntries:     "A kivonatban nincs egyetlen tétel sem."
            }
        }
    }

    // MARK: Bankszámla

    static func importAccount(text: String) throws -> Result {
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var entries: [Entry] = []
        var opening: Decimal = 0
        var closing: Decimal = 0

        let transaction = try! NSRegularExpression(
            pattern: "^(\\d{2}\\.\\d{2}\\.\\d{2}) (\\d{2}\\.\\d{2}\\.\\d{2}) (-?[\\d.]+)$")
        let balance = try! NSRegularExpression(
            pattern: "^(\\d{2}\\.\\d{2}\\.\\d{2}) (-?[\\d.]+)$")

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)

            if let match = transaction.firstMatch(in: line, range: range) {
                guard let day = date(group(match, 1, in: line)),
                      let valueDay = date(group(match, 2, in: line)),
                      let value = amount(group(match, 3, in: line)) else { continue }
                // A megnevezés a KÖVETKEZŐ sor. Ha nincs, a tétel akkor is
                // érvényes — az összeg és a nap a lényeg.
                let text = index + 1 < lines.count ? lines[index + 1] : ""
                entries.append(Entry(date: day, valueDate: valueDay,
                                     text: text, amountHUF: value))
                continue
            }

            if let match = balance.firstMatch(in: line, range: range),
               index + 1 < lines.count,
               let value = amount(group(match, 2, in: line)) {
                let label = lines[index + 1]
                if label.hasPrefix("NYITÓ EGYENLEG") { opening = value }
                if label.hasPrefix("ZÁRÓ EGYENLEG") { closing = value }
            }
        }
        guard !entries.isEmpty else { throw ImportError.noEntries }

        var result = Result(
            kind: .account,
            accountNumber: firstMatch("(?<=SZÁMLASZÁM: )[0-9-]+", in: text) ?? "OTP",
            currency: firstMatch("(?<=DEVIZANEM: )[A-Z]{3}", in: text) ?? "HUF",
            opening: opening, closing: closing, entries: entries,
            statedCredits: value(after: "JÓVÁÍRÁSOK ÖSSZESEN:", in: text),
            statedDebits: value(after: "TERHELÉSEK ÖSSZESEN:", in: text)
        )
        result.warnings = check(result)
        return result
    }

    // MARK: Hitelkártya

    static func importCredit(text: String) throws -> Result {
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var entries: [Entry] = []
        var opening: Decimal = 0
        var closing: Decimal = 0

        // Egy sor: nap, értéknap, megnevezés, majd az összeg a VÉGÉN.
        let transaction = try! NSRegularExpression(
            pattern: "^(\\d{2}\\.\\d{2}\\.\\d{2}) (\\d{2}\\.\\d{2}\\.\\d{2}) (.+?) (-?[\\d.]+)$")
        let balance = try! NSRegularExpression(
            pattern: "^(\\d{2}\\.\\d{2}\\.\\d{2}) (NYITÓ|ZÁRÓ) EGYENLEG (-?[\\d.]+)$")

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)

            if let match = balance.firstMatch(in: line, range: range),
               let value = amount(group(match, 3, in: line)) {
                if group(match, 2, in: line) == "NYITÓ" { opening = value } else { closing = value }
                continue
            }
            if let match = transaction.firstMatch(in: line, range: range),
               let day = date(group(match, 1, in: line)),
               let valueDay = date(group(match, 2, in: line)),
               let value = amount(group(match, 4, in: line)) {
                entries.append(Entry(date: day, valueDate: valueDay,
                                     text: group(match, 3, in: line), amountHUF: value))
            }
        }
        guard !entries.isEmpty else { throw ImportError.noEntries }

        var result = Result(
            kind: .credit,
            accountNumber: firstMatch("(?<=SZÁMLASZÁM: )[0-9-]+", in: text) ?? "OTP-hitelkártya",
            currency: firstMatch("(?<=DEVIZANEM: )[A-Z]{3}", in: text) ?? "HUF",
            opening: opening, closing: closing, entries: entries,
            statedCredits: value(after: "JÓVÁÍRÁSOK ÖSSZESEN:", in: text),
            statedDebits: value(after: "TERHELÉSEK ÖSSZESEN:", in: text),
            totalDebt: value(after: "HITELKÁRTYA TELJES TARTOZÁS:", in: text),
            minimumPayment: value(after: "HITELKÁRTYA MINIMUM FIZETENDŐ ÖSSZEG:", in: text),
            dueDate: firstMatch("(?<=FIZETÉSI HATÁRIDŐ: )\\d{4}\\.\\d{2}\\.\\d{2}", in: text)
                .flatMap { iso in
                    let parts = iso.split(separator: ".").compactMap { Int($0) }
                    guard parts.count == 3 else { return nil }
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
                    return calendar.date(from: DateComponents(year: parts[0], month: parts[1],
                                                              day: parts[2]))
                },
            creditLimit: value(after: "HITELKERET:", in: text)
        )
        result.warnings = check(result)
        return result
    }

    // MARK: - Önellenőrzés

    /// A kivonat kiírja a saját összesítését. Ha a beolvasott tételekből NEM
    /// jön ki ugyanaz, azt jelezzük — csendben rossz számot mutatni rosszabb,
    /// mint bevallani, hogy a beolvasás hiányos.
    private static func check(_ result: Result) -> [String] {
        var warnings: [String] = []
        let credits = result.entries.filter { $0.amountHUF > 0 }
            .reduce(Decimal(0)) { $0 + $1.amountHUF }
        let debits = result.entries.filter { $0.amountHUF < 0 }
            .reduce(Decimal(0)) { $0 + $1.amountHUF }

        if let stated = result.statedCredits, abs((credits - stated).doubleValue) > 1 {
            warnings.append("A jóváírások összege nem egyezik a kivonatéval (\(credits) vs \(stated)).")
        }
        if let stated = result.statedDebits, abs((debits - stated).doubleValue) > 1 {
            warnings.append("A terhelések összege nem egyezik a kivonatéval (\(debits) vs \(stated)).")
        }
        let computed = result.opening + credits + debits
        if abs((computed - result.closing).doubleValue) > 1 {
            warnings.append("A nyitó + forgalom nem adja ki a záró egyenleget (\(computed) vs \(result.closing)).")
        }
        return warnings
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int,
                              in line: String) -> String {
        guard let range = Range(match.range(at: index), in: line) else { return "" }
        return String(line[range])
    }
}
