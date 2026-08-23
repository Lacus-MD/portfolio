import Foundation

/// Az app↔widget közös adatfájl.
///
/// App Group konténerben él, mert a widget-extension külön folyamat: a
/// sima Application Support mappát nem látná. iOS-en a group-azonosító
/// NEM kap team-prefixet (macOS-en kapna — ott a sandbox megköveteli).
enum PortfolioFile {
    static var appGroupID: String { AppGroup.id }

    /// Mi történt betöltéskor. A hívónak tudnia kell, mert az „üres" és a
    /// „nem sikerült elolvasni" két teljesen más helyzet: az elsőre menteni
    /// helyes, a másodikra menteni ADATVESZTÉS.
    enum LoadStatus {
        case ok
        case missing        // még nincs fájl — új telepítés
        case recovered      // a fő fájl sérült, a másolatból jött vissza
        case corrupt        // egyik sem olvasható
    }

    struct Payload: Codable, @unchecked Sendable {
        var holdings: [Holding] = []
        var snapshots: [Snapshot] = []
        /// Forintos befizetések — az XIRR alapja.
        var deposits: [Deposit] = []
        /// Levont díjak, típus szerint bontva.
        var fees: [FeeItem] = []
        /// A követett platformok. Ha üres, a pozíciók számláiból származtatjuk.
        var platforms: [Platform] = []
        /// Kamatozó készpénz-eszközök (Revolut Savings, széf).
        var cashAssets: [CashAsset] = []
        /// Készpénz **számlánként**, azon belül devizánként.
        /// Nem globális: két brókernél két külön egyenleg van.
        var cash: [String: [String: Decimal]] = [:]
        /// Átváltási árrés **számlánként** (pl. 0,0035). Brókerenként más —
        /// a Lightyear 0,35%-a nem a Revoluté —, ezért nem lehet egyetlen szám.
        var conversionSpread: [String: Decimal] = [:]
        /// A TBSZ adókulcsai — szerkeszthetők, mert jogszabályfüggők.
        var tbszRules: TBSZRules?
        /// A forgatókönyv-számoló elmentett feltevései.
        var scenario: Scenario?
        /// Komponensenkénti napi záróár, ISIN → nap → ár.
        ///
        /// Az egyedi részvények TÖRTÉNETI árfolyama nem érhető el ingyenes
        /// forrásból (a Yahoo tartósan 429, a Stooq bot-ellenőrzés mögött, a
        /// Börse Frankfurt history-ja CORS-zárt). Ezért ugyanúgy gyűjtjük,
        /// mint a portfólió-görbét: naponta egy mérés, és a görbe onnantól épül.
        var constituentPrices: [String: [String: Decimal]] = [:]
        /// ISIN → nap („yyyy-MM-dd") → halmozott darabszám. A kivonatból jön,
        /// és a görbe visszatöltése ebből tudja, hány darab volt EGY ADOTT
        /// NAPON — a mai darabszámmal visszaszámolni hamis múltat adna.
        var quantityTimeline: [String: [String: Decimal]] = [:]
        /// Elrejtett hírek hivatkozásai. A dizájn elrejthetővé teszi a
        /// híreket; ha ez nem élné túl az újraindítást, a következő
        /// megnyitásnál visszajönne mind — vagyis nem is lenne elrejtés.
        var hiddenNews: [String] = []
        /// Kiadási tételek a kivonatokból — ebből épül a Kiadások fül.
        var expenses: [ExpenseEntry] = []
        /// Hitelkártyák fizetési adatai a kivonatból.
        var creditCards: [CreditCardStatus] = []
        /// Ügyletjelölők a görbékhez, platformonként.
        var trades: [TradeMarker] = []
        /// A választott színtéma azonosítója.
        var themeID: String = "pastel"
        /// Célallokációs arányok a befektethető vagyonban.
        /// Kulcs: platform azonosító, érték: cél százalék (0...100).
        var allocationTargets: [String: Double] = [:]
        /// Az app utolsó sikeres frissítése — a widget ebből tudja, mennyire friss az adat.
        var lastRefresh: Date?
        /// Utolsó ismert EUR/HUF, hogy a widget offline is tudjon forintosítani.
        var fxRate: Decimal = 0
        /// ISIN → utolsó ismert árfolyam, hogy a widget hálózat nélkül is számoljon.
        var lastPrices: [String: Decimal] = [:]
        /// Platform-azonosító → a bank neve, ha a számla a BANKKAPCSOLATBÓL jön.
        ///
        /// Azért kell, mert a bankkapcsolat nem készít befizetés-tételeket,
        /// csak egyenleget és kiadásokat. Egy megtakarításba átvezetett
        /// összeg párja tehát ott SOHA nem fog megjelenni — ezt tudni kell,
        /// különben az app örökké hiányzó kivonatot kérne olyasmiért, ami
        /// nem hiányzik.
        var bankLinkedPlatforms: [String: String] = [:]
        /// A kártyák KÉZI sorrendje, platform-azonosítókkal.
        ///
        /// Üresen hagyva az érték szerinti csökkenő sorrend marad. Amint
        /// átrendezed, ez veszi át — de csak az itt felsoroltakra: egy új
        /// platform a végére kerül, nem tolja szét a te sorrendedet.
        var platformOrder: [String] = []

        init() {}

        /// Kézzel írt dekódoló — ugyanaz az ok, mint a modelleknél: a Swift
        /// szintetizált változata hiányzó kulcsnál hibát dob az alapérték
        /// helyett. Emiatt minden mezőbővítés dekódolhatatlanná tette a már
        /// mentett állományt, és a rákövetkező mentés felülírta a jó adatot.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            holdings         = try c.decodeIfPresent([Holding].self,          forKey: .holdings) ?? []
            snapshots        = try c.decodeIfPresent([Snapshot].self,         forKey: .snapshots) ?? []
            deposits         = try c.decodeIfPresent([Deposit].self,          forKey: .deposits) ?? []
            fees             = try c.decodeIfPresent([FeeItem].self,          forKey: .fees) ?? []
            platforms        = try c.decodeIfPresent([Platform].self,         forKey: .platforms) ?? []
            cashAssets       = try c.decodeIfPresent([CashAsset].self,        forKey: .cashAssets) ?? []
            // Két alak fordulhat elő: a mostani (számla → deviza → összeg) és
            // a korábbi lapos (deviza → összeg). A régit a meglévő pozíciók
            // számlájához rendeljük, hogy ne vesszen el.
            let fallbackAccount = holdings.first?.account ?? Holding.manualAccount
            if let byAccount = try? c.decode([String: [String: Decimal]].self, forKey: .cash) {
                cash = byAccount
            } else if let flat = try? c.decode([String: Decimal].self, forKey: .cash) {
                cash = [fallbackAccount: flat]
            } else {
                cash = [:]
            }
            tbszRules = try? c.decodeIfPresent(TBSZRules.self, forKey: .tbszRules)
            scenario = try? c.decodeIfPresent(Scenario.self, forKey: .scenario)
            constituentPrices = (try? c.decodeIfPresent([String: [String: Decimal]].self,
                                                        forKey: .constituentPrices)) ?? [:]
            quantityTimeline = (try? c.decodeIfPresent([String: [String: Decimal]].self,
                                                       forKey: .quantityTimeline)) ?? [:]
            hiddenNews = (try? c.decodeIfPresent([String].self, forKey: .hiddenNews)) ?? []
            expenses = (try? c.decodeIfPresent([ExpenseEntry].self, forKey: .expenses)) ?? []
            creditCards = (try? c.decodeIfPresent([CreditCardStatus].self, forKey: .creditCards)) ?? []
            trades = try c.decodeIfPresent([TradeMarker].self, forKey: .trades) ?? []
            themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? "pastel"
            if let byAccount = try? c.decode([String: Decimal].self, forKey: .conversionSpread) {
                conversionSpread = byAccount
            } else if let single = try? c.decode(Decimal.self, forKey: .conversionSpread) {
                conversionSpread = [fallbackAccount: single]
            } else {
                conversionSpread = [:]
            }
            allocationTargets = try c.decodeIfPresent([String: Double].self,
                                                     forKey: .allocationTargets) ?? [:]
            // Ezek a mezők KIMARADTAK a dekódolóból, pedig mentve voltak.
            // Következmény: az utolsó ismert árak és árfolyam minden
            // indításnál elvesztek, tehát az app hálózat nélkül nem tudott
            // értéket mutatni, a widget pedig egyáltalán nem tudott a mentett
            // árakra visszaesni — mindig „nincs friss adat" állapotba került.
            // Mérve: a tárolt állományban ott volt az ár, a betöltött
            // szerkezetben nem.
            lastRefresh = try? c.decodeIfPresent(Date.self, forKey: .lastRefresh)
            fxRate      = try c.decodeIfPresent(Decimal.self, forKey: .fxRate) ?? 0
            lastPrices  = try c.decodeIfPresent([String: Decimal].self, forKey: .lastPrices) ?? [:]
            platformOrder = try c.decodeIfPresent([String].self, forKey: .platformOrder) ?? []
            bankLinkedPlatforms = try c.decodeIfPresent([String: String].self,
                                                        forKey: .bankLinkedPlatforms) ?? [:]
        }
    }

    static var url: URL? { container?.appending(path: "portfolio.json") }

    /// A legutóbbi ÉP állapot másolata. Minden sikeres, nem üres mentésnél
    /// frissül, és sérülés esetén ebből állunk vissza.
    static var backupURL: URL? { container?.appending(path: "portfolio.backup.json") }
    /// A titkosított biztonsági másolat az App Beállításokban választhatóan.
    static var encryptedBackupURL: URL? { container?.appending(path: "portfolio.secure.backup.bin") }

    private static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// A 2026-08-20 előtti hely. Ha ott van adat és a csoportban még nincs,
    /// egyszer átköltöztetjük.
    private static var legacyURL: URL {
        URL.applicationSupportDirectory.appending(path: "portfolio.json")
    }

    private static func decode(_ url: URL?) -> Payload? {
        guard let url, let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Betöltés a sérülés megkülönböztetésével.
    static func loadDetailed() -> (payload: Payload, status: LoadStatus) {
        if let payload = decode(url) { return (payload, .ok) }

        // A fő fájl nem olvasható. Van-e egyáltalán fájl? Ha nincs, ez új
        // telepítés; ha van, akkor sérült, és nem szabad felülírni.
        let mainExists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        if let backup = decode(backupURL) {
            // A sérült fájlt félretesszük, nem dobjuk el — ha valaha kell.
            if mainExists, let url {
                let broken = url.deletingLastPathComponent()
                    .appending(path: "portfolio.broken.json")
                try? FileManager.default.removeItem(at: broken)
                try? FileManager.default.moveItem(at: url, to: broken)
            }
            save(backup)
            return (backup, .recovered)
        }

        if let payload = decode(URL?.some(legacyURL)) {
            save(payload)
            return (payload, .ok)
        }

        if let payload = BackupSecurityManager.load() {
            save(payload)
            return (payload, .recovered)
        }

        return (Payload(), mainExists ? .corrupt : .missing)
    }

    /// Visszafelé kompatibilis alak.
    static func load() -> Payload { loadDetailed().payload }

    static func save(_ payload: Payload) {
        guard let url, let data = try? JSONEncoder().encode(payload) else { return }
        // .atomic: félbeszakadt írás ne hagyjon csonka fájlt a pozíciók helyén.
        try? data.write(to: url, options: .atomic)
        // Másolatot csak ÉRTELMES állapotról készítünk. Üres állományt
        // biztonsági másolatnak elmenteni pont a védelmet semmisítené meg.
        if !payload.holdings.isEmpty, let backupURL {
            try? data.write(to: backupURL, options: .atomic)
        }
    }
}
