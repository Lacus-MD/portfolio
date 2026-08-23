import Foundation

/// A Revolut magyar kivonatainak közös elemzői.
///
/// A két Revolut-formátum kevés dolgot oszt meg, de ezt a kettőt igen:
/// magyar hónapnevek és vesszős tizedes.
enum HungarianCSV {

    /// „2026. máj. 1." → dátum. A magyar hónaprövidítéseket kézzel képezzük le:
    /// a `DateFormatter` a rendszernyelvtől függene, és angol nyelvű
    /// készüléken némán elbukna — pont az a hiba, amit nem szabad megengedni
    /// egy pénzügyi beolvasónál.
    static let months: [String: Int] = [
        "jan": 1, "febr": 2, "feb": 2, "márc": 3, "marc": 3, "ápr": 4, "apr": 4,
        "máj": 5, "maj": 5, "jún": 6, "jun": 6, "júl": 7, "jul": 7,
        "aug": 8, "szept": 9, "szep": 9, "okt": 10, "nov": 11, "dec": 12,
    ]

    static func hungarianDate(_ text: String) -> Date? {
        // „2026. máj. 1." — pontokkal tagolt, a hónap rövidítve.
        let parts = text.split(separator: ".").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty }
        guard parts.count >= 3, let year = Int(parts[0]),
              let month = months[parts[1]], let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Szám kiolvasása a tizedesjel KITALÁLÁSÁVAL, nem feltételezésével.
    ///
    /// Ez korábban feltevés volt: a megtakarítási kivonat vesszős tizedest
    /// használ („1 234,56 HUF"), a folyószámláé pontosat („1234.56"), és a
    /// hívó tudja, melyiket olvassa. A Revolut viszont a KÉSZÜLÉK nyelvén is
    /// exportál, és angol exportban ugyanaz az összeg „400,693.53 HUF".
    /// A régi kód minden pontot ezresjelnek vett, ezért ebből `400.69353`
    /// lett — a telefonon 400 693 Ft helyett **400 Ft** jelent meg, és a
    /// megtakarítás „−99,90%"-ot mutatott. Mérve, nem feltételezve.
    ///
    /// A szabály (ez a szokásos, és mindkét exportra helyes):
    ///   • ha vessző ÉS pont is van, a KÉSŐBBI a tizedesjel, a másik ezres;
    ///   • ha csak az egyik van, akkor tizedesjel, ha pontosan egyszer
    ///     szerepel és utána 1–2 számjegy áll — különben ezreselválasztó;
    ///   • ha egyik sincs, egész szám.
    static func number(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{00A0}", with: "")   // nem törhető szóköz
            .replacingOccurrences(of: "\u{202F}", with: "")   // keskeny nem törhető
            .replacingOccurrences(of: "\u{2009}", with: "")   // vékony szóköz
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        let lastComma = cleaned.lastIndex(of: ",")
        let lastDot = cleaned.lastIndex(of: ".")

        func digitsAfter(_ index: String.Index) -> Int {
            cleaned.distance(from: cleaned.index(after: index), to: cleaned.endIndex)
        }
        func count(_ character: Character) -> Int {
            cleaned.filter { $0 == character }.count
        }

        let decimalSeparator: Character?
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            decimalSeparator = comma > dot ? "," : "."
        case let (comma?, nil):
            decimalSeparator = (count(",") == 1 && (1...2).contains(digitsAfter(comma))) ? "," : nil
        case let (nil, dot?):
            decimalSeparator = (count(".") == 1 && (1...2).contains(digitsAfter(dot))) ? "." : nil
        case (nil, nil):
            decimalSeparator = nil
        }

        if let decimalSeparator {
            let thousands: Character = decimalSeparator == "," ? "." : ","
            cleaned = cleaned.replacingOccurrences(of: String(thousands), with: "")
            cleaned = cleaned.replacingOccurrences(of: String(decimalSeparator), with: ".")
        } else {
            cleaned = cleaned
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
        }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Egyszerű szám pénznem-utótag nélkül („-499.52", „0.00", „21 607,94").
    static func plainAmount(_ text: String) -> Decimal? { number(text) }

    /// „1 234,56 HUF" → (1234.56, "HUF"). A pénznem-utótagot leválasztja,
    /// a számot a fenti szabállyal olvassa.
    static func amount(_ text: String) -> (value: Decimal, currency: String)? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }

        var currency = "HUF"
        let tail = cleaned.suffix(3)
        if tail.count == 3, tail.allSatisfy(\.isUppercase) {
            currency = String(tail)
            cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespaces)
        }
        guard let value = number(cleaned) else { return nil }
        return (value, currency)
    }

    /// ISO alak a folyószámla-kivonatból: „2026-03-05 20:42:28".
    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Budapest")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
