import Foundation

/// Egy kiadás-kategória.
///
/// A `isSpending` a lényeges megkülönböztetés: **nem minden kimenő forint
/// kiadás.** A Lightyearbe vagy a Revolutba átvezetett pénz a saját
/// számládra megy — az app másik füle épp azt követi. Költésként számolva
/// ugyanaz a forint kétszer szerepelne, és a havi „kiadás" több százezerrel
/// tűnne nagyobbnak. Ugyanaz a hiba, mint a befizetéseknél a belső átvezetés.
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case groceries, dining, fuel, transport, travel, home, hygiene, health
    case clothing, electronics, subscriptions, utilities, insurance, leisure
    case loan, savings, cash, fees, transfer, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .groceries:     "Élelmiszer"
        case .dining:        "Étkezés"
        case .fuel:          "Üzemanyag"
        case .transport:     "Közlekedés"
        case .travel:        "Utazás, szállás"
        case .home:          "Otthon"
        case .hygiene:       "Higiénia"
        case .health:        "Egészség"
        case .clothing:      "Ruházat"
        case .electronics:   "Műszaki"
        case .subscriptions: "Előfizetés"
        case .utilities:     "Rezsi"
        case .insurance:     "Biztosítás"
        case .leisure:       "Szabadidő"
        case .loan:          "Hiteltörlesztés"
        case .savings:       "Megtakarítás"
        case .cash:          "Készpénzfelvét"
        case .fees:          "Banki díj"
        case .transfer:      "Átutalás"
        case .other:         "Egyéb"
        }
    }

    var icon: String {
        switch self {
        case .groceries:     "cart"
        case .dining:        "fork.knife"
        case .fuel:          "fuelpump"
        case .transport:     "tram"
        case .travel:        "airplane"
        case .home:          "house"
        case .hygiene:       "drop"
        case .health:        "cross.case"
        case .clothing:      "tshirt"
        case .electronics:   "desktopcomputer"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .utilities:     "bolt"
        case .insurance:     "shield"
        case .leisure:       "theatermasks"
        case .loan:          "banknote"
        case .savings:       "arrow.up.forward.circle"
        case .cash:          "banknote"
        case .fees:          "building.columns"
        case .transfer:      "arrow.left.arrow.right"
        case .other:         "questionmark.circle"
        }
    }

    /// Igaz, ha a költés jórészt FÜGGETLEN a hónapban hozott döntéseidtől:
    /// a törlesztés, a rezsi, a biztosítás, az előfizetések és a banki díjak
    /// akkor is elmennek, ha egy hónapig ki sem lépsz a lakásból. Ez a
    /// szétválasztás adja meg, mennyi mozgástered marad.
    var isFixed: Bool {
        switch self {
        case .loan, .utilities, .insurance, .subscriptions, .fees: true
        default: false
        }
    }

    /// Igaz, ha VALÓDI fogyasztás. A megtakarítás és a saját számlák közti
    /// átvezetés nem az; a hiteltörlesztés vitatható, de kiadás — a pénz
    /// tényleg elmegy —, ezért benne van.
    var isSpending: Bool {
        switch self {
        case .savings, .transfer: false
        default: true
        }
    }
}

/// Kereskedőnév és tranzakciótípus alapján kategóriát ad.
///
/// **Szabályalapú, nem tanuló.** Egy pénzügyi appban a kiszámíthatóság
/// többet ér: ugyanaz a bolt mindig ugyanoda kerül, és ha téved, a szabály
/// javítható. A találatok mérve vannak (lásd README) — ami nem illik
/// szabályra, az `egyéb` marad, nem tippelünk.
enum ExpenseCategorizer {

    /// A kategória-szabályok SORRENDBEN. Az első találat nyer, ezért a
    /// szűkebb minták állnak elöl: a „Revolut" saját átvezetés, nem műszaki
    /// bolt, a „MOL" üzemanyag, nem élelmiszer.
    static let rules: [(ExpenseCategory, [String])] = [
        // Saját számlák — ELŐSZÖR, mert ezek nem kiadások.
        // A WebKincstár állampapír-vásárlás: megtakarítás, nem költés.
        // Mérve: 50 124 Ft esett volna „egyéb" kiadásba.
        (.savings, ["REVOLUT", "LIGHTYEAR", "PERSELY", "WISE", "TRADE REPUBLIC",
                    "INTERACTIVE BROKERS", "MEGTAKARITAS", "WEBKINCSTAR",
                    "KINCSTAR", "ALLAMPAPIR", "MAK "]),
        (.loan, ["HITEL TORL", "KOLCSON TORLESZT", "JELZALOG", "LAKASHITEL",
                 "ARUVASARLASI HITEL", "SZEMELYI KOLCSON"]),
        (.fees, ["BANKKARTYA EVES DIJ", "KARTYAGYARTASI DIJ", "PREMIUM NEXT",
                 "SZAMLAVEZETESI DIJ", "TRANZAKCIOS ILLETEK", "MEGB.DIJ",
                 "MEGBIZASI DIJ", "SMS SZOLGALTATAS"]),
        (.cash, ["KESZPENZFELVET", "ATM"]),
        (.insurance, ["BIZTOSITO", "BIZTOSITAS", "OTTHONBIZT", "GENERALI",
                      "ALLIANZ", "UNIQA", "GROUPAMA", "SIGNAL"]),
        (.utilities, ["MVM", "NKM", "ELMU", "FOGAZ", "TAVKOZLESI", "TELEKOM",
                      "VODAFONE", "YETTEL", "DIGI", "VIZCENTER", "VIZMU",
                      "E-ONKORMANYZAT", "ONKORMANYZAT", "KOZOS KOLTSEG",
                      "HULLADEK", "NHKV", "POSTACSEKK", "MAGYAR POSTA"]),
        (.subscriptions, ["APPLE.COM", "PROTON", "NETFLIX", "SPOTIFY", "GOOGLE *",
                          "DISNEY", "HBO", "MAX.COM", "YOUTUBE", "ICLOUD",
                          "OPENAI", "ANTHROPIC", "MICROSOFT", "ADOBE",
                          "PATREON", "STEAM", "DROPBOX", "NOTION", "GITHUB"]),
        (.fuel, ["MOL ", "OMV", "SHELL", "ORLEN", "AVIA", "LUKOIL", "BENZINKUT"]),
        (.travel, ["BOOKING", "AIRBNB", "RYANAIR", "WIZZ", "HOTEL", "PANZIO",
                   "APARTMAN", "EXPEDIA", "TRIVAGO", "SZALLAS"]),
        (.transport, ["BKK", "MAV ", "VOLANBUSZ", "PARKOL", "NEMZETI MOBILFIZETESI",
                      "MOBILITI", "BOLT.EU", "UBER", "TAXI", "E-MATRICA", "AUTOPALYA"]),
        (.groceries, ["LIDL", "TESCO", "SPAR", "ALDI", "PENNY", "CBA", "COOP",
                      "AUCHAN", "KIFLI.HU", "PRIMA", "REAL ", "ABC", "PIAC",
                      "PEKSEG", "HUSBOLT", "ZOLDSEG", "NESPRESSO", "MEZESVOLGY"]),
        (.dining, ["BISTRO", "BISZTRO", "PIZZ", "RESTAURANT", "ETTEREM", "ETELBAR", "BUFE",
                   "KAVEZO", "CAFE", "COFFEE", "MCD", "BURGER", "KFC", "SUBWAY",
                   "STARBUCKS", "WOLT", "FOODPANDA", "FAGYIZO", "CUKRASZ",
                   "KURTOS", "VIKING", "KONYHA", "GRILL", "SUSHI", "TAVERNA",
                   "TORTA", "BELLOZZO", "BAGEL", "FALATOZO", "KIFOZDE",
                   "PRESSZO", "SOROZO", "BAR ", "DONER", "GYROS"]),
        (.hygiene, ["DM ", "DM3", "ROSSMANN", "MULLER", "DROGERIA", "NOTINO"]),
        (.health, ["PATIKA", "GYOGYSZER", "BENU", "BENU ", "PHARMA", "ORVOS", "KLINIKA",
                   "LABOR", "FOGASZAT", "OPTIKA", "SZEMESZET"]),
        (.home, ["IKEA", "JYSK", "OBI", "BAUHAUS", "PRAKTIKER", "MOM PARK",
                 "KERTESZET", "BARKACS", "PEPCO", "KIK ", "TEDI", "BONAMI",
                 "GEPKOLCSONZ", "SZERSZAM", "MOBELIX", "XXXLUTZ"]),
        (.clothing, ["ANSWEAR", "OYSHO", "H&M", "ZARA", "RESERVED", "CCC",
                     "DEICHMANN", "DECATHLON", "SPORTISIMO", "INTERSPORT",
                     "HERVIS", "NIKE", "ADIDAS", "SPRINGFIELD", "MANGO", "BERSHKA"]),
        (.leisure, ["JATEK", "REGIO", "LIBRI", "KONYV", "MOZI", "CINEMA",
                    "SZINHAZ", "KONCERT", "USZODA", "FITNESS", "EDZOTEREM",
                    "MUZEUM", "ALLATKERT", "JEGY.HU", "TICKET", "NINTENDO",
                    "PLAYSTATION", "XBOX", "WHOOP", "STRAVA"]),
        (.electronics, ["ALZA", "MEDIA MARKT", "EMAG", "EDIGITAL", "ARUKERESO",
                        "IPON", "PCLAND"]),
        // Az általános átutalás-típusok a VÉGÉN: ezek bármit takarhatnak,
        // ezért csak akkor nyernek, ha semmi konkrétabb nem illett.
        (.transfer, ["AZONNALI FIZETES", "NAPKOZBENI ATUTALAS", "QVIK",
                     "ATUTALAS", "ATVEZETES", "CSOPORTOS BESZEDES"]),
    ]

    /// Ékezet- és kisbetű-független alak. A kivonatok hol ékezettel, hol
    /// anélkül írják ugyanazt a boltot (`GÖDÖLLÕ` vs `GODOLLO`), és a PDF
    /// szövegrétegében az `õ`/`ő` is keveredik.
    static func normalize(_ text: String) -> String {
        // A PDF szövegrétegében keverednek a kódlap-maradványok: a `GÖDÖLLŐ`
        // hol `GÖDÖLLÕ`, hol `G÷d÷ll÷` alakban jön. Az ékezet-hajtogatás az
        // elsőt megoldja, a másodikat nem — a `÷` nem ékezetes betű, hanem
        // egy rossz kódlapból származó jel. Ezért kézzel is leképezzük.
        var text = text
        for (wrong, right) in [("÷", "o"), ("Ø", "O"), ("ð", "o"), ("þ", "u")] {
            text = text.replacingOccurrences(of: wrong, with: right)
        }
        return text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                            locale: Locale(identifier: "hu_HU")).uppercased()
    }

    static func categorize(_ description: String) -> ExpenseCategory {
        let text = normalize(description)
        for (category, keywords) in rules where keywords.contains(where: { text.contains($0) }) {
            return category
        }
        return .other
    }

    /// A kereskedő neve a tétel leírásából, emberi alakban.
    ///
    /// A kártyás sorok gépi mezőket is tartalmaznak (kártyaszám, azonosító,
    /// tranzakciódátum); a bolt neve ezek UTÁN áll. Ha nem találjuk, a
    /// tranzakció típusát adjuk vissza — az mindig ott van.
    static func merchant(from description: String) -> String {
        let parts = description.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2 else { return description }

        // Az utolsó olyan mező, ami nem csak számokból/dátumból áll.
        let candidates = parts.dropFirst().filter { part in
            let stripped = part.replacingOccurrences(of: "Tranzakció: ", with: "")
            guard stripped.count >= 3 else { return false }
            // Csupa szám, csillag vagy dátum → gépi mező.
            let letters = stripped.filter { $0.isLetter }
            guard letters.count >= 3 else { return false }
            // A devizajelölő mező („25EUR") pont három betűs, tehát átcsúszna
            // a fenti szűrőn. Mérve: emiatt lett három tétel kereskedője
            // „25EUR" a valódi „WHOOP" helyett.
            return stripped.range(of: "^[0-9.,]*[A-Z]{3}$", options: .regularExpression) == nil
        }
        var name = candidates.first ?? parts[0]
        for suffix in [" -APPLE", " -GOOGLE", " -SAMSUNG"] {
            name = name.replacingOccurrences(of: suffix, with: "")
        }
        // A devizás utótag („10,320EUR 0,") nem a bolt neve.
        if let range = name.range(of: "[0-9]+,[0-9]+[A-Z]{3}", options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }
        return name.trimmingCharacters(in: .whitespaces).isEmpty
            ? parts[0] : name.trimmingCharacters(in: .whitespaces)
    }
}
