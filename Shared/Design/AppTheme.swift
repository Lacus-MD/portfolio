import SwiftUI

/// Egy teljes színséma világos és sötét módra.
///
/// Minden téma ugyanazokat a SZEREPEKET tölti ki, nem konkrét színeket:
/// vászon, kártya, szöveg, „héj" (a részletképernyők alapja) és három
/// akcentus. Így a nézetek nem tudják, melyik téma aktív — csak szerepeket
/// kérnek.
///
/// **A három akcentus NEM „meleg / hűvös / köztes" többé.** Eredetileg az
/// volt, és ezért nézett ki minden téma narancsvezérelten: az első akcentus
/// mindig meleg narancs volt, azt viszi az app kiemelőszíne, az első
/// platformkártya, a jelvény és az összetétel-gyűrű legnagyobb szelete.
/// Most a három akcentus HARMÓNIA-SÉMÁBÓL jön, témánként másikból
/// (komplementer, osztott-komplementer, triád, analóg, tetrád, kettős), és a
/// vezető árnyalat is minden témánál más. A mezőnevek történetiek — a
/// `accentWarm` az ELSŐ akcentust jelenti, nem azt, hogy meleg.
///
/// **A Pasztell sem kivétel többé.** Az eredeti handoff-paletta korallal
/// (35°) vezetett; mivel az első akcentust viszi az app kiemelőszíne, az
/// első platformkártya, a jelvény, az összetétel-gyűrű és a chipek, ettől az
/// egész app narancsnak látszott. Most 330°-ról (rózsa) indul, a jellege —
/// krémes vászon, mély szilva héj — viszont megmarad, mert az is a vezető
/// árnyalatból származik. Az eredeti hexek a README-ben megvannak.
///
/// A színek OKLCH-ban készültek, azonos érzékelt világossággal (L = 0,76):
/// sRGB-ben az „egyforma világosság" nem ellenőrizhető, OKLabban igen. A
/// szövegszín az akcentuson MÉRT WCAG-kontraszt alapján dől el, nem ránézésre.
struct AppTheme: Identifiable, Codable, Hashable {
    var id: String
    var name: String

    // Világos mód
    var canvasLight: UInt32
    var cardLight: UInt32
    var inkLight: UInt32

    // Sötét mód
    var canvasDark: UInt32
    var cardDark: UInt32
    var inkDark: UInt32

    /// A részletképernyők alapja és lapja SÖTÉT módban.
    var shellDeep: UInt32
    var shell: UInt32

    /// Ugyanaz VILÁGOS módban. A sötét héjú témáknál ez azonos a sötét
    /// párjával — azok szándékosan sötét héjjal készültek. A világos héjú
    /// témák itt tényleg világos árnyalatot adnak, és akkor a héjon a szöveg
    /// sem lehet fehér: azt az `inkOnShellLight` mondja meg.
    var shellDeepLight: UInt32
    var shellLight: UInt32
    var inkOnShellLight: UInt32

    /// Igaz, ha világos módban a részletlapok is világosak.
    var hasLightShell: Bool

    /// A HAT akcentus, sorrendben. Mind azonos OKLab-világosságú, csak az
    /// árnyalatuk tér el — így a platformkártyák egymás mellett
    /// kiegyensúlyozottak maradnak.
    ///
    /// Korábban három volt. Négy platformtól kezdve ismétlődött a szín, és a
    /// kártyák egymáshoz hasonlítottak. Az első három árnyalat SZÁNDÉKOSAN
    /// változatlan, hogy a meglévő platformok színe ne mozduljon el.
    var accents: [UInt32]

    /// Szöveg az egyes akcentusokon. **Mért érték**, nem feltevés: a
    /// generátor MINDEGYIK akcentusra kiszámolja a fehér és a saját sötét
    /// tónus WCAG-kontrasztját, és a jobbikat teszi ide. Korábban az első
    /// akcentuson fixen fehér állt (mért kontraszt: 2,25 — olvashatatlan
    /// kis szövegre); most 7,1 fölött van mindenhol.
    var inkOnAccents: [UInt32]

    /// Nyereség- és veszteség-szín.
    ///
    /// **Nem akcentus.** Korábban a nyereség a második akcentust vitte, ami az
    /// eredeti pasztell témában véletlenül zöld volt. Amint a témák saját
    /// harmónia-sémát kaptak, a második akcentus lehetett lazac vagy sárga —
    /// és egy „+0,03%" pirosan jelent meg. Ez a kettő ezért rögzített
    /// árnyalaton áll (zöld 152°, piros 25°), csak a telítettségük követi a témát.
    var positive: UInt32
    var negative: UInt32

    /// Hat ikonszín, a három akcentuson TÚL, szerepekhez kötve (deviza,
    /// árfolyam, nyertes, vesztes, hír, idő) — a `DS.Color.Icon` sorolja fel.
    var iconHues: [UInt32]

    static let all: [AppTheme] = [
        // Sötét héjú (a részletlapok mindkét módban sötétek)
        pastel, ocean, forest, graphite, midnight, charcoal, basalt, cherry,
        // Világos héjú
        paper, dawn, sand, lavender,
    ]

    static var darkShelled: [AppTheme] { all.filter { !$0.hasLightShell } }
    static var lightShelled: [AppTheme] { all.filter(\.hasLightShell) }

    static func named(_ id: String) -> AppTheme {
        all.first { $0.id == id } ?? pastel
    }

    /// Pasztell — osztott-komplementer harmónia a(z) 330°-os vezető árnyalatra.
    /// Akcentusok: 330° / 120° / 180° / 0° / 150° / 300°, azonos OKLab-világossággal (0.76).
    static let pastel = AppTheme(
        id: "pastel", name: "Pasztell",
        canvasLight: 0xFBF3FA, cardLight: 0xFFFDFE, inkLight: 0x392737,
        canvasDark: 0x1D141C, cardDark: 0x2C212B, inkDark: 0xF2EAF1,
        shellDeep: 0x1A0E18, shell: 0x2B1D2A,
        shellDeepLight: 0x1A0E18, shellLight: 0x2B1D2A, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0xD09ECB, 0xAAB97C, 0x70C3B3, 0xDF9BAF, 0x8AC195, 0xB9A5E0],
        inkOnAccents: [0x331931, 0x212805, 0x002B25, 0x391723, 0x0D2B15, 0x281D3A],
        positive: 0x5E9D70, negative: 0xC5514C,
        iconHues: [0xC690C0, 0xD78C97, 0xA8AA64, 0x64B79C, 0x5BB2CC, 0x999EDE]
    )

    /// Tenger — komplementer harmónia a(z) 205°-os vezető árnyalatra.
    /// Akcentusok: 205° / 25° / 55° / 235° / 355° / 175°, azonos OKLab-világossággal (0.76).
    static let ocean = AppTheme(
        id: "ocean", name: "Tenger",
        canvasLight: 0xEAF9FB, cardLight: 0xFAFEFF, inkLight: 0x113437,
        canvasDark: 0x081A1C, cardDark: 0x14292C, inkDark: 0xE3F0F1,
        shellDeep: 0x011619, shell: 0x09282B,
        shellDeepLight: 0x011619, shellLight: 0x09282B, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0x57C3CF, 0xEA9891, 0xE3A072, 0x6DBBE8, 0xE496B4, 0x64C6AD],
        inkOnAccents: [0x022A2E, 0x3B1816, 0x381C06, 0x00283B, 0x381825, 0x002C23],
        positive: 0x539F6A, negative: 0xC5514C,
        iconHues: [0x3AB8C5, 0x67ABE4, 0xD589B4, 0xDD8E6B, 0xBAA44F, 0x69B987]
    )

    /// Erdő — osztott-komplementer harmónia a(z) 148°-os vezető árnyalatra.
    /// Akcentusok: 148° / 298° / 358° / 178° / 328° / 118°, azonos OKLab-világossággal (0.76).
    static let forest = AppTheme(
        id: "forest", name: "Erdő",
        canvasLight: 0xF0F9F0, cardLight: 0xFBFFFB, inkLight: 0x203322,
        canvasDark: 0x101A11, cardDark: 0x1D291E, inkDark: 0xE7EFE8,
        shellDeep: 0x09160B, shell: 0x18271A,
        shellDeepLight: 0x09160B, shellLight: 0x18271A, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0x8AC191, 0xB8A5E3, 0xE099B1, 0x6CC4B1, 0xD19DCE, 0xACB977],
        inkOnAccents: [0x0E2B14, 0x271D3B, 0x391724, 0x012B24, 0x321A31, 0x222704],
        positive: 0x5B9D6E, negative: 0xC5514C,
        iconHues: [0x7AB682, 0x50B8B0, 0xA19BDE, 0xD28BAF, 0xDA8F78, 0xB5A55B]
    )

    /// Grafit — analóg harmónia a(z) 255°-os vezető árnyalatra.
    /// Akcentusok: 255° / 289° / 221° / 323° / 187° / 357°, azonos OKLab-világossággal (0.76).
    static let graphite = AppTheme(
        id: "graphite", name: "Grafit",
        canvasLight: 0xF3F6FB, cardLight: 0xFDFDFE, inkLight: 0x272E38,
        canvasDark: 0x14171C, cardDark: 0x21262B, inkDark: 0xEAEDF1,
        shellDeep: 0x0E1319, shell: 0x1E232B,
        shellDeepLight: 0x0E1319, shellLight: 0x1E232B, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0x9EB3CE, 0xB0ADCD, 0x92B8C5, 0xBFA8C2, 0x91BBB6, 0xCAA6B1],
        inkOnAccents: [0x10253E, 0x231F3D, 0x012934, 0x311A33, 0x002B28, 0x381824],
        positive: 0x699A76, negative: 0xC5514C,
        iconHues: [0x91A7C3, 0xA69FC1, 0xC19A90, 0xAEA582, 0x92AD92, 0x81AEB3]
    )

    /// Éjkék — triád harmónia a(z) 272°-os vezető árnyalatra.
    /// Akcentusok: 272° / 32° / 152° / 332° / 92° / 212°, azonos OKLab-világossággal (0.76).
    static let midnight = AppTheme(
        id: "midnight", name: "Éjkék",
        canvasLight: 0xF3F5FE, cardLight: 0xFDFDFF, inkLight: 0x272D42,
        canvasDark: 0x131722, cardDark: 0x202433, inkDark: 0xE9ECF7,
        shellDeep: 0x0E1221, shell: 0x1D2234,
        shellDeepLight: 0x0E1221, shellLight: 0x1D2234, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0x97ACFA, 0xF19583, 0x76C68D, 0xDC95D2, 0xCBAF54, 0x42C4DB],
        inkOnAccents: [0x1B223E, 0x3A1912, 0x0B2B16, 0x331930, 0x2D2300, 0x002A31],
        positive: 0x47A265, negative: 0xC5514C,
        iconHues: [0x899FF2, 0xBF8DDD, 0xE18D57, 0xA7AC47, 0x4EBD8D, 0x29B5DC]
    )

    /// Szén — kettős harmónia a(z) 330°-os vezető árnyalatra.
    /// Akcentusok: 330° / 30° / 160° / 0° / 100° / 220°, azonos OKLab-világossággal (0.76).
    static let charcoal = AppTheme(
        id: "charcoal", name: "Szén",
        canvasLight: 0xF9F4F8, cardLight: 0xFFFDFE, inkLight: 0x342A33,
        canvasDark: 0x1B151A, cardDark: 0x292328, inkDark: 0xF0EBEF,
        shellDeep: 0x171016, shell: 0x282027,
        shellDeepLight: 0x171016, shellLight: 0x282027, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0xC4A6C0, 0xCFA69E, 0x96BBA6, 0xCDA4B0, 0xB8B28E, 0x8EB9C7],
        inkOnAccents: [0x331931, 0x3A1813, 0x042C1B, 0x391723, 0x2A2401, 0x002934],
        positive: 0x699A76, negative: 0xC5514C,
        iconHues: [0xB999B5, 0xC4979D, 0xA6A881, 0x83B09F, 0x7FADBC, 0x9DA1C7]
    )

    /// Bazalt — komplementer harmónia a(z) 185°-os vezető árnyalatra.
    /// Akcentusok: 185° / 5° / 35° / 215° / 335° / 155°, azonos OKLab-világossággal (0.76).
    static let basalt = AppTheme(
        id: "basalt", name: "Bazalt",
        canvasLight: 0xEBFAF7, cardLight: 0xF9FFFE, inkLight: 0x123430,
        canvasDark: 0x091B19, cardDark: 0x142A27, inkDark: 0xE3F0EE,
        shellDeep: 0x001715, shell: 0x0A2825,
        shellDeepLight: 0x001715, shellLight: 0x0A2825, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0x55C7BA, 0xEA95A8, 0xEC9983, 0x54C2DB, 0xDB98CC, 0x78C594],
        inkOnAccents: [0x012B27, 0x391720, 0x3A1911, 0x012932, 0x34192E, 0x082C18],
        positive: 0x4FA069, negative: 0xC5514C,
        iconHues: [0x37BBAE, 0x44B3DA, 0xC98BCC, 0xE38780, 0xCE9A4C, 0x85B56B]
    )

    /// Cseresznye — triád harmónia a(z) 15°-os vezető árnyalatra.
    /// Akcentusok: 15° / 135° / 255° / 75° / 195° / 315°, azonos OKLab-világossággal (0.76).
    static let cherry = AppTheme(
        id: "cherry", name: "Cseresznye",
        canvasLight: 0xFEF3F3, cardLight: 0xFFFDFD, inkLight: 0x402527,
        canvasDark: 0x211314, cardDark: 0x322021, inkDark: 0xF6E9EA,
        shellDeep: 0x1F0C0E, shell: 0x321B1D,
        shellDeepLight: 0x1F0C0E, shellLight: 0x321B1D, inkOnShellLight: 0xFFFFFF,
        hasLightShell: false,
        accents: [0xE9979D, 0x96C07F, 0x85B4F0, 0xD6A866, 0x57C5C5, 0xC99EDD],
        inkOnAccents: [0x3A181B, 0x182A0D, 0x10253E, 0x331F00, 0x022A2A, 0x2E1B36],
        positive: 0x539F6A, negative: 0xC5514C,
        iconHues: [0xE0888F, 0xD99260, 0x69B987, 0x41B5CF, 0x83A3E9, 0xC78DCA]
    )

    /// Papír — triád harmónia a(z) 95°-os vezető árnyalatra.
    /// Akcentusok: 95° / 215° / 335° / 155° / 275° / 35°, azonos OKLab-világossággal (0.76).
    static let paper = AppTheme(
        id: "paper", name: "Papír",
        canvasLight: 0xFFFEFC, cardLight: 0xF2F0E7, inkLight: 0x332E1A,
        canvasDark: 0x1A170D, cardDark: 0x28251A, inkDark: 0xEFEDE5,
        shellDeep: 0x161306, shell: 0x272314,
        shellDeepLight: 0xFCFBF7, shellLight: 0xF1EFE6, inkOnShellLight: 0x332E1A,
        hasLightShell: true,
        accents: [0xC0B17A, 0x77BECF, 0xD09FC4, 0x8BC09C, 0xA3AEE1, 0xDCA091],
        inkOnAccents: [0x2C2300, 0x012932, 0x34192E, 0x082C18, 0x1C213E, 0x3A1911],
        positive: 0x659B73, negative: 0xC5514C,
        iconHues: [0xB4A469, 0x8FB07D, 0x71ADD0, 0xA89BD3, 0xCA90B0, 0xD0957A]
    )

    /// Hajnal — analóg harmónia a(z) 350°-os vezető árnyalatra.
    /// Akcentusok: 350° / 24° / 316° / 58° / 282° / 92°, azonos OKLab-világossággal (0.76).
    static let dawn = AppTheme(
        id: "dawn", name: "Hajnal",
        canvasLight: 0xFFFEFE, cardLight: 0xF9ECF1, inkLight: 0x3D2531,
        canvasDark: 0x201319, cardDark: 0x2F2027, inkDark: 0xF4E9EE,
        shellDeep: 0x1D0D15, shell: 0x2F1C25,
        shellDeepLight: 0xFEFAFC, shellLight: 0xF8EBF0, inkOnShellLight: 0x3D2531,
        hasLightShell: true,
        accents: [0xDF98BA, 0xE79994, 0xC99FDA, 0xDFA274, 0xA7AAEC, 0xC7B068],
        inkOnAccents: [0x371828, 0x3B1817, 0x2E1B36, 0x371C05, 0x20203E, 0x2D2300],
        positive: 0x579E6C, negative: 0xC5514C,
        iconHues: [0xD58AAE, 0xDD8C7E, 0x8FB26C, 0x46B9B3, 0x64ADDE, 0xAE96DC]
    )

    /// Homok — tetrád harmónia a(z) 65°-os vezető árnyalatra.
    /// Akcentusok: 65° / 155° / 265° / 110° / 210° / 355°, azonos OKLab-világossággal (0.76).
    static let sand = AppTheme(
        id: "sand", name: "Homok",
        canvasLight: 0xFEFEFE, cardLight: 0xF7EEE7, inkLight: 0x3B2A19,
        canvasDark: 0x1E150D, cardDark: 0x2D2319, inkDark: 0xF3EBE5,
        shellDeep: 0x1B1006, shell: 0x2D2013,
        shellDeepLight: 0xFEFAF6, shellLight: 0xF6EDE6, inkOnShellLight: 0x3B2A19,
        hasLightShell: true,
        accents: [0xD7A677, 0x85C19A, 0x97B1E8, 0xB4B676, 0x6BC0CF, 0xDD9BB4],
        inkOnAccents: [0x361E02, 0x082C18, 0x17233F, 0x262601, 0x002A30, 0x381825],
        positive: 0x5E9D70, negative: 0xC5514C,
        iconHues: [0xCD9966, 0xADA862, 0x54B5C0, 0x88A4DF, 0xBA93CC, 0xD88D92]
    )

    /// Levendula — osztott-komplementer harmónia a(z) 295°-os vezető árnyalatra.
    /// Akcentusok: 295° / 85° / 145° / 325° / 115° / 265°, azonos OKLab-világossággal (0.76).
    static let lavender = AppTheme(
        id: "lavender", name: "Levendula",
        canvasLight: 0xFEFEFF, cardLight: 0xF0EEF9, inkLight: 0x2F2A40,
        canvasDark: 0x181520, cardDark: 0x262330, inkDark: 0xEDEBF5,
        shellDeep: 0x14101E, shell: 0x242031,
        shellDeepLight: 0xFBFAFE, shellLight: 0xEFEDF8, inkOnShellLight: 0x2F2A40,
        hasLightShell: true,
        accents: [0xB5A6E5, 0xCBAD6D, 0x8DC18E, 0xCF9ED1, 0xAFB875, 0x95B0EB],
        inkOnAccents: [0x261E3C, 0x302100, 0x112B12, 0x311A33, 0x232703, 0x17233F],
        positive: 0x5B9D6E, negative: 0xC5514C,
        iconHues: [0xA998DB, 0xCB8DBD, 0xC89C5C, 0x8AB374, 0x52B8AC, 0x6FABDE]
    )
}