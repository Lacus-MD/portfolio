import Foundation

/// Egy ügylet jelölése a görbén.
///
/// A dátum és az irány elég — az összeget a lista mutatja. A görbén csak azt
/// akarjuk látni, MIKOR nyúltál a portfólióhoz, hogy az elmozdulásokat ehhez
/// lehessen kötni.
struct TradeMarker: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case buy, sell }

    var id: String { "\(platform)-\(day)-\(kind.rawValue)" }
    var platform: String
    /// Nap-kulcs (`yyyy-MM-dd`), hogy a JSON-ban olvasható és stabil legyen.
    var day: String
    var kind: Kind

    init(platform: String, day: String, kind: Kind) {
        self.platform = platform; self.day = day; self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform = try c.decode(String.self, forKey: .platform)
        day      = try c.decode(String.self, forKey: .day)
        kind     = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .buy
    }
}
