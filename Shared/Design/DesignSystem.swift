import SwiftUI
import Observation

/// A 2026-08-21-i pasztell redizájn tokenjei.
/// A handoff „high-fidelity": a színek, méretek és sugarak véglegesek.
enum DS {

    // MARK: - Színek

    enum Color {

        /// Az aktív téma. A tár tölti be induláskor; a nézetek csak SZEREPEKET
        /// kérnek (vászon, kártya, szöveg, akcentus), nem konkrét színeket.
        ///
        /// **Megfigyelhető tároló mögött áll.** Korábban ez egy sima globális
        /// változó volt, amiről a SwiftUI nem tudott, ezért témaváltáskor az
        /// egész nézetfát újra kellett építeni (`.id(themeID)`) — az app
        /// láthatóan „újraindult", elveszett a görgetés és a kiválasztott fül.
        /// Így viszont a színek olvasása a `body`-ban FÜGGŐSÉGET regisztrál,
        /// és váltáskor pontosan azok a nézetek rajzolódnak újra, amelyek
        /// tényleg használják a témát — állapotvesztés nélkül.
        static var theme: AppTheme {
            get { ActiveTheme.shared.value }
            set { ActiveTheme.shared.value = newValue }
        }

        // MARK: Rendszertémához igazodó szerepek
        //
        // Nem `@Environment(\.colorScheme)`-mel: dinamikus `UIColor`-ral minden
        // nézet magától követi a rendszert, és nem kell a témát kézzel átfűzni.

        #if os(iOS)
        private static func adaptive(_ light: UInt32, _ dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(UIColor { traits in
                UIColor(SwiftUI.Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
            })
        }
        #else
        // A watchOS mindig sötét, és nincs dinamikus UIColor.
        private static func adaptive(_ light: UInt32, _ dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(hex: dark)
        }
        #endif

        /// A képernyő alapja.
        static var canvas: SwiftUI.Color { adaptive(theme.canvasLight, theme.canvasDark) }
        /// Kártyák, listasorok háttere a vásznon.
        static var card: SwiftUI.Color { adaptive(theme.cardLight, theme.cardDark) }
        /// Elsődleges szövegszín a vásznon.
        static var ink: SwiftUI.Color { adaptive(theme.inkLight, theme.inkDark) }
        static func inkSoft(_ alpha: Double) -> SwiftUI.Color { ink.opacity(alpha) }

        /// A részletképernyők alapja és lapja.
        ///
        /// A régi négy témánál ez mindkét módban sötét — így készültek. Az
        /// újabb, világos héjú témáknál (Papír, Hajnal, Homok) világos módban
        /// világos árnyalat jön. Ezért **nem szabad fehér szöveget írni rájuk**:
        /// arra `onShell(_:)` van, ami követi a héjat.
        static var plumDeep: SwiftUI.Color { adaptive(theme.shellDeepLight, theme.shellDeep) }
        static var plum: SwiftUI.Color { adaptive(theme.shellLight, theme.shell) }

        /// A három platform-akcentus.
        /// A platform-akcentus sorszám szerint. A `%` nem díszítés: ha egy
        /// téma valaha kevesebb akcentust adna, itt körbefordul, nem omlik.
        static func accent(_ index: Int) -> SwiftUI.Color {
            let list = theme.accents
            guard !list.isEmpty else { return SwiftUI.Color(hex: 0xD09ECB) }
            return SwiftUI.Color(hex: list[index % list.count])
        }

        static func inkOnAccent(_ index: Int) -> SwiftUI.Color {
            let list = theme.inkOnAccents
            guard !list.isEmpty else { return SwiftUI.Color(hex: 0x331931) }
            return SwiftUI.Color(hex: list[index % list.count])
        }

        static var coral: SwiftUI.Color { accent(0) }
        static var mint: SwiftUI.Color { accent(1) }
        static var lilac: SwiftUI.Color { accent(2) }

        /// Szöveg az akcentusokon — MÉRT kontraszt alapján, témánként.
        static var inkCoral: SwiftUI.Color { inkOnAccent(0) }
        static var inkMint: SwiftUI.Color { inkOnAccent(1) }
        static var inkLilac: SwiftUI.Color { inkOnAccent(2) }

        /// Nyereség. NEM akcentus — lásd az `AppTheme.positive` magyarázatát.
        static var positiveGreen: SwiftUI.Color { SwiftUI.Color(hex: theme.positive) }
        static var negativeCream: SwiftUI.Color { SwiftUI.Color(hex: theme.negative) }
        /// A vászon VILÁGOS változata, a rendszer beállításától függetlenül.
        ///
        /// Csak akkor szabad használni, ahol tényleg fix világos folt kell —
        /// például egy sötét kártyán ülő pötty. **Háttérnek tilos**: a
        /// navigációs sáv ezt kapta, ezért sötét módban világos sáv ült a lap
        /// tetején, olvashatatlan világos szöveggel. Oda `canvas` kell, ami
        /// követi a rendszert.
        static var alwaysLight: SwiftUI.Color { SwiftUI.Color(hex: theme.canvasLight) }

        /// Nyereség/veszteség szín. A jelet a szám előjele és a nyíl is hordozza,
        /// hogy színtévesztéssel is olvasható maradjon.
        static func sign(_ value: Double) -> SwiftUI.Color {
            if value > 0 { return positiveGreen }
            if value < 0 { return negativeCream }
            return .gray
        }

        /// Szöveg a héjon. Sötét héjon fehér, világos héjon sötét tinta —
        /// ez az egyetlen helyes forma héj fölött, a nyers `.white` nem az.
        static func onShell(_ alpha: Double = 1) -> SwiftUI.Color {
            adaptive(theme.inkOnShellLight, 0xFFFFFF).opacity(alpha)
        }
        /// Régi név, ugyanaz a szerep.
        static func onPlum(_ alpha: Double = 1) -> SwiftUI.Color { onShell(alpha) }

        // MARK: Ikonszínek
        //
        // A sorikonok korábban mind a három platform-akcentusból jöttek, ezért
        // egy lista egyhangúnak látszott, és a szín nem jelentett semmit.
        // Szerephez kötve viszont hordoz információt: a deviza mindig ugyanaz a
        // szín, a nyertes és a vesztes egymás ellentéte, és így tovább.

        enum Icon: Int, CaseIterable {
            case warm = 0, mid, cool, amber, sky, rose
        }

        static func icon(_ role: Icon) -> SwiftUI.Color {
            let hues = theme.iconHues
            guard !hues.isEmpty else { return coral }
            return SwiftUI.Color(hex: hues[role.rawValue % hues.count])
        }

        /// Deviza — mindig ugyanaz a hue, hogy a szem megtanulja.
        static var iconFX: SwiftUI.Color { icon(.mid) }
        /// Árfolyam.
        static var iconPrice: SwiftUI.Color { icon(.warm) }
        /// Aki nagyot nyert.
        static var iconWinner: SwiftUI.Color { icon(.cool) }
        /// Aki nagyot bukott — ez NEM a hibapiros, hanem a téma meleg hue-ja;
        /// a hibapirost a figyelmeztetéseknek tartjuk fenn.
        static var iconLoser: SwiftUI.Color { icon(.rose) }
        static var iconNews: SwiftUI.Color { icon(.sky) }
        static var iconTime: SwiftUI.Color { icon(.amber) }
        /// Szöveg krémszínű (vászon) háttéren — visszafelé kompatibilis alak.
        static func onCream(_ alpha: Double = 1) -> SwiftUI.Color { ink.opacity(alpha) }
    }

    // MARK: - Tipográfia
    //
    // A handoff Poppinst ír elő. A rendszer nem tartalmazza, ezért ha a
    // betűkészlet nincs beágyazva, a `rounded` SF-re esünk vissza — az áll
    // hozzá a legközelebb súlyban és karakterben. A `fontExists` ellenőrzés
    // futásidejű, hogy a beágyazás bármikor pótolható legyen újrafordítás nélkül.

    static let fontFamily = "Poppins"

    private static let hasPoppins: Bool = {
        #if canImport(UIKit)
        return UIFont(name: fontFamily, size: 12) != nil
        #else
        return false
        #endif
    }()

    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        guard hasPoppins else { return .system(size: size, weight: weight, design: .rounded) }
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Poppins-Bold"
        case .semibold:             name = "Poppins-SemiBold"
        case .medium:               name = "Poppins-Medium"
        default:                    name = "Poppins-Regular"
        }
        return .custom(name, fixedSize: size)
    }

    /// A handoff típusskálája, névvel.
    static var display: Font   { font(44, .bold) }      // összeg
    static var stat: Font      { font(20, .medium) }
    static var cardTitle: Font { font(17, .semibold) }
    static var screenTitle: Font { font(17, .medium) }
    static var headerName: Font { font(16, .semibold) }
    static var section: Font   { font(14, .medium) }
    static var button: Font    { font(14, .medium) }
    static var rowTitle: Font  { font(13.5, .medium) }
    // A handoff 10,5/12 pt-je papíron jól nézett ki, kézben viszont apró.
    // Egy fokkal feljebb vittük — az arányok maradnak, az olvashatóság javul.
    static var label: Font     { font(13, .regular) }
    static var meta: Font      { font(12, .regular) }
    static var badge: Font     { font(11, .medium) }
    static var monogram: Font  { font(12, .semibold) }

    // MARK: - Sugarak és térközök

    enum R {
        static let platformCard: CGFloat = 36
        static let sheet: CGFloat = 34
        static let primaryButton: CGFloat = 26
        static let sheetButton: CGFloat = 22
        static let ctaPill: CGFloat = 20
        static let chip: CGFloat = 14
        static let rowIcon: CGFloat = 14
        static let valueTag: CGFloat = 12
        static let bar: CGFloat = 5
    }

    /// A státuszsáv biztonságos zónáját a handoff felső paddinggel nyeli el
    /// (a nézetek `ignoresSafeArea(edges: .top)`-ot használnak).
    ///
    /// 58-ról 78-ra emelve: a tulajdonos szerint a tartalom túl magasan
    /// kezdődött, és a Dinamikus Sziget alatt szorosnak hatott. A 78 az a
    /// magasság, ahol a fejléc a szigettől elválik, és ahol a rendszer nagy
    /// címsoros lapjai (Hírek, Beállítások) is kezdik a tartalmat — így a
    /// négy fül végre egy vonalban indul.
    static let topPadding: CGFloat = 78

    /// Hely a lebegő fül-sávnak. A tab bar RÁÚSZIK a tartalomra, tehát a
    /// görgetés végén enélkül az utolsó kártya alatta marad, élesen elvágva.
    /// Egy helyen áll, hogy a lapok ne csússzanak el egymástól.
    static let bottomPadding: CGFloat = 132
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}


/// Az aktív téma megfigyelhető tárolója.
///
/// Nem `@MainActor`: a widget és a megosztás-kiterjesztés külön folyamatban,
/// nem feltétlenül a fő szálon olvassa. A kockázat ugyanaz, mint a korábbi
/// `nonisolated(unsafe)` globálisé volt — írni csak a beállításokból írjuk,
/// a fő szálról.
@Observable
final class ActiveTheme: @unchecked Sendable {
    static let shared = ActiveTheme()
    var value: AppTheme = .pastel
    private init() {}
}
