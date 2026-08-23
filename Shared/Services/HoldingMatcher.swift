import Foundation

/// Melyik komponensről szól egy hírcím.
///
/// A társítás **szóhatáros**, nem részsztring: a „meta" különben beletalálna a
/// „metaverse"-be és a „metal"-ba, a „micron" a „micronutrient"-be. Egy
/// pénzügyi hírfolyamban ez nem elméleti kockázat.
///
/// A nevek pontosan úgy szerepelnek, ahogy a `FundComposition` szeleteiben —
/// enélkül a csoportosítás nem érne össze a listával.
enum HoldingMatcher {

    /// Komponensnév → keresőszavak. Tömb, nem szótár: a szótár bejárási
    /// sorrendje nem determinisztikus, és két találatnál más-más csoportba
    /// kerülne ugyanaz a hír két futáskor.
    static let aliases: [(name: String, words: [String])] = [
        ("NVIDIA",     ["nvidia"]),
        ("Apple",      ["apple"]),
        ("Microsoft",  ["microsoft"]),
        ("Amazon",     ["amazon"]),
        ("Alphabet A", ["alphabet", "google"]),
        ("TSMC",       ["tsmc", "taiwan semiconductor", "taiwan semi"]),
        ("Broadcom",   ["broadcom"]),
        ("Micron",     ["micron"]),
        ("Meta",       ["meta", "facebook", "instagram", "whatsapp"]),
    ]

    /// Minden keresőszó egyben — a relevancia-szűrő ezt használja.
    static let allWords: [String] = aliases.flatMap(\.words)

    static func match(_ title: String) -> String? {
        let lower = title.lowercased()
        for entry in aliases where entry.words.contains(where: { contains(lower, $0) }) {
            return entry.name
        }
        return nil
    }

    static func containsAny(_ title: String) -> Bool { match(title) != nil }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }
}
