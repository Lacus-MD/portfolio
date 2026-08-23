import Foundation

/// `Decimal` → `Double`. Számításnál és rajzolásnál kell; a tárolás marad
/// `Decimal`, mert pénzt lebegőpontosan tartani hibás.
extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

enum Fmt {
    private static let hungarian = Locale(identifier: "hu_HU")

    static func huf(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.locale = hungarian
        f.numberStyle = .currency
        f.currencyCode = "HUF"
        f.maximumFractionDigits = 0
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    static func eur(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = hungarian
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    /// Rövidített összeg a widgetre, ahol nincs hely a teljes számnak: 11,4 M Ft.
    static func compact(_ value: Decimal, currency: String) -> String {
        let d = value.doubleValue
        let unit = currency == "HUF" ? "Ft" : "€"
        switch abs(d) {
        case 1_000_000...: return String(format: "%.1f M %@", d / 1_000_000, unit)
                              .replacingOccurrences(of: ".", with: ",")
        case 10_000...:    return String(format: "%.0f e %@", d / 1_000, unit)
        default:           return currency == "HUF" ? huf(value) : eur(value, fractionDigits: 0)
        }
    }

    /// Magyar tizedesvesszővel. A `String(format:)` mindig pontot ír, ami
    /// magyarul hibás — és a felület minden százaléka ezen ment át.
    static func percent(_ value: Double, digits: Int = 2) -> String {
        let f = NumberFormatter()
        f.locale = hungarian
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.positivePrefix = "+"
        let number = f.string(from: NSNumber(value: value)) ?? "—"
        return number + "%"
    }

    static func signedEUR(_ value: Decimal) -> String {
        (value >= 0 ? "+" : "") + eur(value)
    }

    /// Darabszám magyar ezres-tagolással: 3 747, nem 3,747.
    static func count(_ value: Int) -> String {
        let f = NumberFormatter()
        f.locale = hungarian
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Százalék előjel nélkül, magyar tizedesvesszővel.
    static func percentPlain(_ value: Double, digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = hungarian
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return (f.string(from: NSNumber(value: value)) ?? "—") + "%"
    }

    /// `min`: kötelező tizedesek. Árnál kell: a „265,2" és a „295,65"
    /// egymás alatt ugráló oszlopot ad, ami egy táblázatban zavaró.
    static func decimal(_ value: Decimal, min: Int = 0, max: Int = 4) -> String {
        let f = NumberFormatter()
        f.locale = hungarian
        f.numberStyle = .decimal
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    /// „2026. augusztus" — a Kiadások fül fejléce.
    static func month(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = hungarian
        f.dateFormat = "yyyy. MMMM"
        return f.string(from: date)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(hungarian))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(hungarian))
    }
}

/// HTML-entitások visszafejtése hírcímekben.
///
/// Az RSS-csatornák vegyesen használnak nevesített (`&amp;`, `&apos;`) és
/// számkódos (`&#39;`, `&#8217;`) entitásokat, és a kettő keveredik is. A
/// kézzel felsorolt néhány darab kevés volt: a képernyőn `Nvidia&apos;s`
/// jelent meg. A számkódosakat ezért ÁLTALÁNOSAN oldjuk fel, nem egyesével.
enum HTMLEntities {

    private static let named: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
        "&apos;": "'", "&nbsp;": "\u{00A0}", "&hellip;": "…",
        "&mdash;": "—", "&ndash;": "–", "&lsquo;": "\u{2018}",
        "&rsquo;": "\u{2019}", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
    ]

    static func decode(_ text: String) -> String {
        var value = text
        // Előbb a számkódosak: `&#39;` és `&#x27;` alakban is jönnek.
        while let range = value.range(of: "&#(x?[0-9A-Fa-f]+);", options: .regularExpression) {
            let body = value[range].dropFirst(2).dropLast()
            let scalar: Unicode.Scalar?
            if body.first == "x" || body.first == "X" {
                scalar = UInt32(body.dropFirst(), radix: 16).flatMap(Unicode.Scalar.init)
            } else {
                scalar = UInt32(body).flatMap(Unicode.Scalar.init)
            }
            // Ismeretlen kód: kiszedjük, de nem hagyjuk végtelen ciklusban.
            value.replaceSubrange(range, with: scalar.map { String(Character($0)) } ?? "")
        }
        for (entity, replacement) in named {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        // Az `&amp;` MINDIG utoljára, különben egy `&amp;#39;` kétszer oldódna.
        return value.replacingOccurrences(of: "&amp;", with: "&")
    }
}
