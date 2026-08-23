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
        // A kártyák szerepe állandó, a tényleges árnyalat viszont MINDIG az
        // aktív témából érkezik. Így az öt tipikus számla külön színt kap,
        // miközben témaváltáskor együtt mozdul a teljes felülettel.
        let accentIndex: Int?
        let accent: Color
        switch platform.kind {
        case .credit:
            accentIndex = nil
            accent = DS.Color.negativeCream
        case .savings:
            accentIndex = 3
            accent = DS.Color.accent(3)
        case .current:
            if platform.name.localizedCaseInsensitiveContains("revolut") {
                accentIndex = 4
                accent = DS.Color.accent(4)
            } else {
                accentIndex = 2
                accent = DS.Color.accent(2)
            }
        case .brokerage:
            accentIndex = platform.accent.index
            accent = platform.accent.color
        }

        let adjacent = DS.Color.accent(((accentIndex ?? 0) + 1) % max(DS.Color.theme.accents.count, 1))

        if featured {
            return .init(
                baseColors: [DS.Color.plum, DS.Color.plumDeep],
                cornerColors: [accent, adjacent],
                ink: DS.Color.onShell(),
                accent: accent,
                ringTrack: DS.Color.onShell(0.22),
                badgeFill: DS.Color.onShell(0.08),
                shadow: accent.opacity(0.16)
            )
        }

        return .init(
            baseColors: [DS.Color.card, DS.Color.canvas],
            cornerColors: [accent, adjacent],
            ink: DS.Color.ink,
            accent: accent,
            ringTrack: DS.Color.inkSoft(0.11),
            badgeFill: accent.opacity(0.10),
            shadow: accent.opacity(0.13)
        )
    }
}
