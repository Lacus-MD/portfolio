import SwiftUI

/// A platform-akcentus EGYETLEN forrása.
///
/// Ugyanez a leképzés korábban négy fájlban élt külön `switch`-ként
/// (`HomeView`, az azóta megszűnt `CompareView`, `PlatformCard`,
/// `PlatformDetailView`), és el is
/// csúsztak egymástól: a kártya a második akcentus helyett a héjat rajzolta,
/// a részletnézet viszont a valódi akcentust — ezért ugyanaz a platform két
/// képernyőn más színű volt.
///
/// Az enum esetnevei (`coral`, `mint`, `lilac`) TÖRTÉNETIEK: a mentett
/// adatban ezek a nyers értékek, ezért nem átnevezhetők. Ma egyszerűen az
/// első, második és harmadik akcentust jelentik — hogy melyik árnyalat, azt
/// az aktív téma harmónia-sémája dönti el.
extension Platform.Accent {

    /// A platform színe: kitöltés jelvényen, kártyán, görbén.
    var color: Color { DS.Color.accent(index) }

    /// Szöveg ezen a színen. Mért WCAG-kontraszt alapján a témából jön —
    /// nem fixen fehér, mert egy világos akcentuson a fehér olvashatatlan.
    var ink: Color { DS.Color.inkOnAccent(index) }

}

/// A kezdőképernyő kártyáinak színreceptje.
///
/// A világos lapok pasztell alapot kapnak, a jobb felső sarokban pedig a
/// Figma Color Palettes hideg/meleg színsorából származó, lokalizált fényt.
/// Nem teljes felületű gradient: a kártya nagy része nyugodt és jól olvasható
/// marad, a sarokátmenet csak az azonosítást és a mélységet adja.
struct PlatformCardPalette {
    let baseColors: [Color]
    let cornerColors: [Color]
    let ink: Color
    let accent: Color
    let ringTrack: Color
    let badgeFill: Color
    let shadow: Color

    static func resolve(for platform: Platform, featured: Bool) -> Self {
        if featured {
            return .init(
                baseColors: [Color(hex: 0x182440), Color(hex: 0x0D1830)],
                cornerColors: [Color(hex: 0x536CFF), Color(hex: 0x6F58E8)],
                ink: .white,
                accent: Color(hex: 0xA9B8FF),
                ringTrack: .white.opacity(0.27),
                badgeFill: .white.opacity(0.09),
                shadow: .black.opacity(0.18)
            )
        }

        switch platform.kind {
        case .credit:
            return .peach
        case .savings:
            return .mint
        case .current:
            // A két tranzakciós számla egymás mellett is azonnal
            // megkülönböztethető. Más szolgáltatók a banki kék receptet kapják.
            return platform.name.localizedCaseInsensitiveContains("revolut")
                ? .lilac : .periwinkle
        case .brokerage:
            return platform.accent.index.isMultiple(of: 2) ? .periwinkle : .lilac
        }
    }

    private static let commonInk = Color(hex: 0x142754)

    private static let periwinkle = Self(
        baseColors: [Color(hex: 0xF3F5FF), Color(hex: 0xE7ECFF)],
        cornerColors: [Color(hex: 0x806CFF), Color(hex: 0x6489F5)],
        ink: commonInk,
        accent: Color(hex: 0x4D6FE8),
        ringTrack: commonInk.opacity(0.12),
        badgeFill: Color(hex: 0x536FE4).opacity(0.10),
        shadow: Color(hex: 0x536FE4).opacity(0.15)
    )

    private static let mint = Self(
        baseColors: [Color(hex: 0xF1F9F2), Color(hex: 0xE2F4E9)],
        cornerColors: [Color(hex: 0x62B64C), Color(hex: 0x2D9B7B)],
        ink: commonInk,
        accent: Color(hex: 0x3C9A50),
        ringTrack: commonInk.opacity(0.11),
        badgeFill: Color(hex: 0x3C9A50).opacity(0.10),
        shadow: Color(hex: 0x3C9A50).opacity(0.13)
    )

    private static let lilac = Self(
        baseColors: [Color(hex: 0xF8EEF8), Color(hex: 0xECE8FF)],
        cornerColors: [Color(hex: 0x775FE8), Color(hex: 0x5542AC)],
        ink: commonInk,
        accent: Color(hex: 0x8D4FA8),
        ringTrack: commonInk.opacity(0.11),
        badgeFill: Color(hex: 0x8D4FA8).opacity(0.10),
        shadow: Color(hex: 0x775FE8).opacity(0.13)
    )

    private static let peach = Self(
        baseColors: [Color(hex: 0xFFF1E9), Color(hex: 0xFFE0D5)],
        cornerColors: [Color(hex: 0xFF9A76), Color(hex: 0xEF4E3D)],
        ink: commonInk,
        accent: Color(hex: 0xE94B35),
        ringTrack: commonInk.opacity(0.10),
        badgeFill: Color(hex: 0xE94B35).opacity(0.10),
        shadow: Color(hex: 0xE94B35).opacity(0.13)
    )
}
