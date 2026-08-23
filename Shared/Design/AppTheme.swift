import Foundation
import SwiftUI

/// Az app megjelenése a készülék beállítását követheti, vagy kézzel
/// világosra/sötétre rögzíthető. Az érték az App Groupban él, így egy új
/// folyamat is ugyanazzal a választással indul.
enum AppAppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    private static let defaultsKey = "appearanceMode"
    private static let appGroup = "group.hu.halasz.portfolio"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Rendszer"
        case .light: "Világos"
        case .dark: "Sötét"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static var stored: AppAppearanceMode {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        guard let rawValue = defaults.string(forKey: defaultsKey) else { return .system }
        return AppAppearanceMode(rawValue: rawValue) ?? .system
    }

    func persist() {
        let defaults = UserDefaults(suiteName: Self.appGroup) ?? .standard
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Egy teljes, szerepalapú színrendszer világos és sötét módra.
///
/// A témák az új galériában mindig párok: a világos paletta mellé ugyanannak
/// a színvilágnak egy mély, kontrasztos sötét változata tartozik. A nézetek
/// továbbra sem konkrét hexeket, hanem szerepeket kérnek a DesignSystemtől.
struct AppTheme: Identifiable, Codable, Hashable {
    var id: String
    var name: String

    var canvasLight: UInt32
    var cardLight: UInt32
    var inkLight: UInt32

    var canvasDark: UInt32
    var cardDark: UInt32
    var inkDark: UInt32

    var shellDeep: UInt32
    var shell: UInt32
    var shellDeepLight: UInt32
    var shellLight: UInt32
    var inkOnShellLight: UInt32
    var hasLightShell: Bool

    var accents: [UInt32]
    var inkOnAccents: [UInt32]
    var positive: UInt32
    var negative: UInt32
    var iconHues: [UInt32]

    /// A korábbi azonosítók szándékosan megmaradtak: így a már kiválasztott
    /// téma és az alternatív app-ikon neve frissítés után sem vész el.
    static let all: [AppTheme] = [
        pastel, ocean, forest, graphite, midnight, charcoal,
        basalt, cherry, paper, dawn, sand, lavender, monochrome,
    ]

    static var darkShelled: [AppTheme] { all.filter { !$0.hasLightShell } }
    static var lightShelled: [AppTheme] { all.filter(\.hasLightShell) }

    static func named(_ id: String) -> AppTheme {
        all.first { $0.id == id } ?? pastel
    }

    static let pastel = make(
        id: "pastel", name: "Kagylópart",
        canvasLight: 0xFFF5F2, cardLight: 0xFFFFFF, inkLight: 0x26383A,
        canvasDark: 0x12282D, cardDark: 0x1D353A, inkDark: 0xF7ECE8,
        shellLight: 0xFDE2DC,
        accents: [0xFC4360, 0xFBAA89, 0xF9C4B8, 0xAED3D5, 0xF7CA7F, 0x68C8C5]
    )

    static let ocean = make(
        id: "ocean", name: "Limonádé",
        canvasLight: 0xFFF9E8, cardLight: 0xFFFFFF, inkLight: 0x243737,
        canvasDark: 0x102A29, cardDark: 0x1A3937, inkDark: 0xF7F1DB,
        shellLight: 0xF4E7BA,
        accents: [0x8FD8D5, 0xF4DFA7, 0xF3BC7B, 0xA7D58C, 0xF6C9A5, 0x66C4B7]
    )

    static let forest = make(
        id: "forest", name: "Ananász",
        canvasLight: 0xFFF3EE, cardLight: 0xFFFFFF, inkLight: 0x3B2927,
        canvasDark: 0x2A191B, cardDark: 0x39272A, inkDark: 0xF8E9E4,
        shellLight: 0xF4D8CF,
        accents: [0xF0C8BF, 0xDF8C89, 0xF2A172, 0xF5C584, 0xA8BA8B, 0x7FC8B1]
    )

    static let graphite = make(
        id: "graphite", name: "Lagúna",
        canvasLight: 0xFFF8E6, cardLight: 0xFFFFFF, inkLight: 0x223C45,
        canvasDark: 0x142A32, cardDark: 0x203941, inkDark: 0xF7EFE0,
        shellLight: 0xE8F3ED,
        accents: [0xFF7C70, 0xFFBF9B, 0xFFE7B8, 0x7AD7C1, 0x2A4A57, 0x67B6C9]
    )

    static let midnight = make(
        id: "midnight", name: "Medence",
        canvasLight: 0xF1FBFC, cardLight: 0xFFFFFF, inkLight: 0x173B4B,
        canvasDark: 0x102535, cardDark: 0x1B3547, inkDark: 0xEDF7FA,
        shellLight: 0xDDF4F4,
        accents: [0xFF967F, 0x2489CE, 0x1DB9BC, 0xB8E5E3, 0xF4DCE0, 0x65B7D8]
    )

    static let charcoal = make(
        id: "charcoal", name: "Sorbet",
        canvasLight: 0xFFF8E1, cardLight: 0xFFFFFF, inkLight: 0x2D4443,
        canvasDark: 0x143031, cardDark: 0x203E3E, inkDark: 0xFFF4DC,
        shellLight: 0xE6F1DD,
        accents: [0xFFF0B8, 0xBDE3E1, 0x51C1BF, 0xFFB49B, 0xFF825B, 0x7AB8D6]
    )

    static let basalt = make(
        id: "basalt", name: "Naplemente",
        canvasLight: 0xFFF3F1, cardLight: 0xFFFFFF, inkLight: 0x33313A,
        canvasDark: 0x28202A, cardDark: 0x382D38, inkDark: 0xF8ECEE,
        shellLight: 0xF0DDE0,
        accents: [0xEFC4CB, 0x73B4C1, 0x49A6A0, 0xEFB17F, 0xD99692, 0x7B9EBB]
    )

    static let cherry = make(
        id: "cherry", name: "Fantázia",
        canvasLight: 0xF5F4F0, cardLight: 0xFFFFFF, inkLight: 0x32333B,
        canvasDark: 0x242630, cardDark: 0x323641, inkDark: 0xF1EFE9,
        shellLight: 0xE2DDD6,
        accents: [0x9DA084, 0xBBCDB3, 0xAAB3C3, 0xDBACB5, 0xD3C0B1, 0xFA9950]
    )

    static let paper = make(
        id: "paper", name: "Kerámia",
        canvasLight: 0xF7F5F3, cardLight: 0xFFFFFF, inkLight: 0x383538,
        canvasDark: 0x25262B, cardDark: 0x34353B, inkDark: 0xF2ECE8,
        shellLight: 0xE8E1DD,
        accents: [0xC4B6B4, 0xB6B3C6, 0xA7BDCF, 0xACC9BF, 0xF0BF8B, 0xE99A58]
    )

    static let dawn = make(
        id: "dawn", name: "Cukorfelhő",
        canvasLight: 0xF8F3FF, cardLight: 0xFFFFFF, inkLight: 0x2C3048,
        canvasDark: 0x22263B, cardDark: 0x303650, inkDark: 0xF3EEFA,
        shellLight: 0xE9DFF5,
        accents: [0xE8A7CD, 0x66C4D8, 0x8FA8DE, 0x73D0C2, 0xF7C6D8, 0xB8A1D8]
    )

    static let sand = make(
        id: "sand", name: "Nyaralás",
        canvasLight: 0xFFF8EC, cardLight: 0xFFFFFF, inkLight: 0x24413F,
        canvasDark: 0x092C2C, cardDark: 0x153E3D, inkDark: 0xFFF5DF,
        shellLight: 0xF6E8C7,
        accents: [0xF5A7B8, 0xEC1F69, 0x8AC4C1, 0x109996, 0xF3D66F, 0xFFB154]
    )

    static let lavender = make(
        id: "lavender", name: "Macaron",
        canvasLight: 0xFFF5FA, cardLight: 0xFFFFFF, inkLight: 0x382D3B,
        canvasDark: 0x2C1E2B, cardDark: 0x3C2A3A, inkDark: 0xF8EDF5,
        shellLight: 0xF0DFEA,
        accents: [0xC29AC7, 0x55B8C6, 0xC98BAE, 0xDED17E, 0x99C9B1, 0xEF8D9A]
    )

    /// Szándékosan visszafogott, majdnem teljesen színtelen felület.
    /// Az erős színek csak interaktív kiemeléseken, adatsorokon és kisebb
    /// állapotjelzőkön jelennek meg — nem színezik be a vásznat vagy a kártyát.
    static let monochrome = make(
        id: "monochrome", name: "Monokróm",
        canvasLight: 0xF3F3F1, cardLight: 0xFFFFFF, inkLight: 0x161616,
        canvasDark: 0x090909, cardDark: 0x191919, inkDark: 0xF5F5F2,
        shellLight: 0xE7E7E4,
        accents: [0xFFA500, 0xB22222, 0x111184, 0xCCFF00, 0xFFED29, 0x7C7C78]
    )

    private static func make(
        id: String,
        name: String,
        canvasLight: UInt32,
        cardLight: UInt32,
        inkLight: UInt32,
        canvasDark: UInt32,
        cardDark: UInt32,
        inkDark: UInt32,
        shellLight: UInt32,
        accents: [UInt32]
    ) -> AppTheme {
        AppTheme(
            id: id, name: name,
            canvasLight: canvasLight, cardLight: cardLight, inkLight: inkLight,
            canvasDark: canvasDark, cardDark: cardDark, inkDark: inkDark,
            shellDeep: canvasDark, shell: cardDark,
            shellDeepLight: canvasLight, shellLight: shellLight,
            inkOnShellLight: inkLight, hasLightShell: true,
            accents: accents,
            inkOnAccents: accents.map { bestInk(on: $0, darkInk: inkLight) },
            positive: 0x4F9B68, negative: 0xC95555,
            iconHues: accents
        )
    }

    private static func bestInk(on background: UInt32, darkInk: UInt32) -> UInt32 {
        let lightInk: UInt32 = 0xFFFFFF
        return contrast(background, darkInk) >= contrast(background, lightInk)
            ? darkInk : lightInk
    }

    private static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let brighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (brighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ value: UInt32) -> Double {
        let components = [value >> 16, value >> 8, value].map {
            linear(Double($0 & 0xFF) / 255)
        }
        return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
