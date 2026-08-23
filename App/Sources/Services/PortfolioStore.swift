import Foundation
import UIKit
import Observation
import WidgetKit

@MainActor
@Observable
final class PortfolioStore {
    private(set) var holdings: [Holding] = []
    private(set) var snapshots: [Snapshot] = []
    /// ISIN → legutóbb lekért árfolyam.
    private(set) var quotes: [String: Quote] = [:]
    private(set) var fxRate: Decimal = 0
    private(set) var deposits: [Deposit] = []
    private(set) var fees: [FeeItem] = []
    private(set) var platforms: [Platform] = []
    private(set) var cashAssets: [CashAsset] = []
    private(set) var cash: [String: [String: Decimal]] = [:]
    private(set) var conversionSpread: [String: Decimal] = [:]
    private(set) var tbszRules: TBSZRules?
    private(set) var trades: [TradeMarker] = []
    /// Célallokációs százalékok a befektethető vagyon platformjaira.
    ///
    /// A felhasználó célállítása; minden kulcs egy platform-id, az érték
    /// százalék. A célértékek mentése ugyanúgy a tárolás része.
    private(set) var allocationTargets: [String: Double] = [:]
    /// Melyik platform jön a bankkapcsolatból, és melyik banktól.
    var bankLinkedPlatforms: [String: String] = [:]

    // MARK: - Származtatott adatok gyorsítótára
    //
    // A kezdőképernyő KILENCSZER kérte le a `platformSummaries`-t egyetlen
    // képfrissítés alatt (jelmagyarázat, kártyák, görbe-sorozatok, hiányzó
    // adatok szűrése…), és mindegyik hívás végigszámolta az összes platform
    // értékét és befizetését. Görgetés közben ez képkockánként ismétlődött —
    // innen az akadás.
    //
    // A gyorsítótár `@ObservationIgnored`: nem szabad, hogy az ÍRÁSA nézet-
    // változásnak számítson, különben a rajzolás közbeni írás miatt a
    // SwiftUI körbe-újraépítene. A megfigyelést a getter külön biztosítja —
    // lásd ott.
    @ObservationIgnored var summariesCache: (stamp: DerivedStamp, value: [PlatformSummary])?

    /// Olcsó ujjlenyomat arról, amiből az összesítés készül. Ha ez azonos,
    /// az eredmény is azonos — nem kell újraszámolni.
    struct DerivedStamp: Equatable {
        let holdings: Int, deposits: Int, platforms: Int, cashAssets: Int
        let quotes: Int, cash: Int, order: Int
        let fxRate: Decimal
        let quotesSum: Decimal
        /// Minden mentés lépteti. A puszta DARABSZÁM nem elég: egy kivonat
        /// újraolvasása töröl és visszatesz ugyanannyi tételt, más
        /// összegekkel — a számláló ezt is elkapja.
        let mutation: Int
    }

    /// Minden mentésnél nő. Lásd a `DerivedStamp.mutation` magyarázatát.
    @ObservationIgnored private(set) var mutationCount = 0
    func bumpMutation() { mutationCount &+= 1 }

    /// A getterben olvassuk EZEKET, hogy a SwiftUI megfigyelése akkor is
    /// felépüljön, amikor a gyorsítótárból válaszolunk. Enélkül a nézet nem
    /// értesülne az adatváltozásról, és beragadna a régi számokon.
    var derivedStamp: DerivedStamp {
        DerivedStamp(holdings: holdings.count, deposits: deposits.count,
                     platforms: platforms.count, cashAssets: cashAssets.count,
                     quotes: quotes.count, cash: cash.count,
                     order: platformOrder.count, fxRate: fxRate,
                     // Az árfolyamok ÉRTÉKE is számít, nem csak a darabszámuk:
                     // frissítéskor a kulcsok ugyanazok maradnak.
                     quotesSum: quotes.values.reduce(Decimal(0)) { $0 + $1.price },
                     mutation: mutationCount)
    }
    /// A kártyák kézi sorrendje. Írásra a `movePlatforms` való — az ment is.
    /// Szándékosan NINCS `didSet`: a betöltés is ír rá, és akkor minden
    /// indítás fölöslegesen visszamentené a fájlt.
    var platformOrder: [String] = []
    /// ISIN → nap → halmozott darabszám a kivonatból. A visszatöltés ebből
    /// tudja, hány darab volt egy adott napon.
    private(set) var quantityTimeline: [String: [String: Decimal]] = [:]
    /// Elrejtett hírek hivatkozásai.
    private(set) var hiddenNews: Set<String> = []
    private(set) var expenses: [ExpenseEntry] = []
    private(set) var creditCards: [CreditCardStatus] = []
    private(set) var themeID: String = "pastel"
    private(set) var scenario: Scenario?
    private(set) var usdRate: Decimal = 0
    private(set) var fxDate: Date?
    private(set) var fxSource: String = ""

    var isRefreshing = false
    var lastError: String?
    var lastRefresh: Date?

    private let quoteService = QuoteService()
    private let fxService = FXService()

    /// Igaz, ha a lemezről már betöltöttünk. A `save()` enélkül nem ír —
    /// lásd ott a magyarázatot.
    private var hasLoaded = false

    init() {
        // A betöltés MINDIG az init-ben történik, nem `.task`-ban.
        //
        // Korábban a `PortfolioApp` egy `.task { store.load() }`-dal töltött be,
        // a főnézetnek viszont saját `.task`-ja van, ami frissít. A
        // SwiftUI nem garantálja a két task sorrendjét: ha a nézeté futott
        // előbb, a `refresh()` ÜRES pozíciólistával futott le, és a végén a
        // `save()` kiírta az üres állapotot a fájlra — vagyis eldobta az
        // adatot. Ezért volt esetleges: versenyhelyzet volt.
        load()
    }

    // MARK: - Származtatott értékek

    var totalValueEUR: Decimal {
        holdings.reduce(0) { sum, h in
            sum + (quotes[h.isin].map { h.quantity * $0.price } ?? 0)
        }
    }
    var totalCostEUR: Decimal { holdings.reduce(0) { $0 + $1.costBasis } }

    /// A forintos bekerülési érték — csak akkor van, ha MINDEN pozíciónál
    /// megvan. Fél adatból számolt devizahatás rosszabb, mint semmi.
    var totalCostHUF: Decimal? {
        guard !holdings.isEmpty, holdings.allSatisfy({ $0.costHUF != nil }) else { return nil }
        return holdings.reduce(Decimal(0)) { $0 + ($1.costHUF ?? 0) }
    }

    var currencySplit: Analytics.CurrencySplit? {
        Analytics.currencySplit(valueEUR: totalValueEUR, costEUR: totalCostEUR,
                                costHUF: totalCostHUF, fxNow: fxRate)
    }

    var xirr: Double? {
        guard netValueHUF > 0 else { return nil }
        // A ténylegesen realizálható értékkel számolunk, nem a papírossal.
        return Analytics.xirr(deposits: deposits, currentValueHUF: netValueHUF)
    }

    /// Egyetlen platform befizetés-súlyozott éves hozama. A platform-képernyőn
    /// a teljes portfólió XIRR-jét mutatni félrevezető lenne.
    func xirr(ofPlatform id: String) -> Double? {
        let own = deposits.filter { $0.account == id }
        let value = valueHUF(ofPlatform: id)
        guard !own.isEmpty, value > 0 else { return nil }
        return Analytics.xirr(deposits: own, currentValueHUF: value)
    }

    /// Hány napja fut a követés ezen a platformon.
    func trackedDays(ofPlatform id: String) -> Int? {
        Analytics.trackedDays(deposits.filter { $0.account == id })
    }

    var feeSummary: Analytics.FeeSummary? { Analytics.fees(fees, deposits: deposits) }

    var totalDepositedHUF: Decimal { deposits.reduce(0) { $0 + $1.amountHUF } }
    /// Középárfolyamos forintérték — az alap „papíron" ennyit ér.
    var totalValueHUF: Decimal { totalValueEUR * fxRate }

    /// A brókernél álló készpénz forintban.
    /// Az összes számla készpénze forintban.
    var cashHUF: Decimal {
        cash.values.flatMap { $0 }.reduce(Decimal(0)) { sum, entry in
            switch entry.key {
            case "HUF": return sum + entry.value
            case "EUR": return sum + entry.value * fxRate
            case "USD": return sum + (usdRate > 0 ? entry.value * usdRate : 0)
            default:    return sum
            }
        }
    }

    /// Egy számla árrése. Ismeretlen számlánál nulla — inkább ne vonjunk le
    /// semmit, mint hogy egy másik bróker árrését alkalmazzuk rá.
    func spread(for account: String) -> Decimal { conversionSpread[account] ?? 0 }

    /// Amit ténylegesen kapnál, ha ma eladnál és forintra váltanál:
    /// a befektetések középárfolyamos értéke az átváltási árréssel csökkentve,
    /// plusz a számlán álló készpénz.
    ///
    /// A bróker is így értékel — ezt mértük: az árréssel csökkentett összeg
    /// hat forinton belül egyezett azzal, amit a Lightyear kijelez. Középárfolyamon
    /// számolva az app rendre magasabb, tehát optimistább számot mutatna.
    var netValueHUF: Decimal {
        // Pozíciónként a SAJÁT számlája árrésével — brókerenként más —,
        // plusz a brókernél álló készpénz, plusz a kamatozó megtakarítások.
        //
        // A megtakarítások BENNE VANNAK: enélkül az XIRR a teljes befizetést
        // hasonlítaná a csak-értékpapír értékhez, és irreális veszteséget mutatna.
        let securities = holdings.reduce(Decimal(0)) { $0 + (netValueHUF(for: $1) ?? 0) }
        let savings = cashAssets.reduce(Decimal(0)) {
            $0 + convertToHUF($1.estimatedBalance(), currency: $1.currency)
        }
        return securities + cashHUF + savings
    }

    /// Hozam a befizetésekhez mérve — „kezdetektől". Ez a bróker mércéje is:
    /// mennyit tettél be összesen, és mennyi van most. A díjak automatikusan
    /// benne vannak veszteségként, mert csökkentik a mai értéket.
    var gainVsDeposits: Decimal? {
        guard totalDepositedHUF > 0, !holdings.isEmpty else { return nil }
        return netValueHUF - totalDepositedHUF
    }

    var gainVsDepositsPercent: Double? {
        guard let gain = gainVsDeposits, totalDepositedHUF > 0 else { return nil }
        return (gain / totalDepositedHUF).doubleValue * 100
    }
    var totalGainEUR: Decimal { totalValueEUR - totalCostEUR }
    var totalGainPercent: Double {
        guard totalCostEUR > 0 else { return 0 }
        return (totalGainEUR / totalCostEUR).doubleValue * 100
    }

    /// A tegnapi mentéshez képesti napi változás. Csak akkor ad értéket, ha
    /// tényleg van korábbi mérés — becsült számot nem gyártunk.
    var dayChangeEUR: Decimal? {
        let today = Calendar.current.startOfDay(for: Date())
        guard let previous = snapshots.filter({ $0.date < today }).max(by: { $0.date < $1.date })
        else { return nil }
        return totalValueEUR - previous.valueEUR
    }

    func value(for holding: Holding) -> Decimal? {
        quotes[holding.isin].map { holding.quantity * $0.price }
    }

    /// A pozíció FORINTOS értéke ugyanazzal a mércével, mint a fejléc:
    /// árréssel csökkentve. Enélkül a sorok összege nem adná ki az összesent,
    /// és a felhasználó jogosan hinné, hogy valamelyik szám hibás.
    func netValueHUF(for holding: Holding) -> Decimal? {
        guard let value = value(for: holding) else { return nil }
        return value * fxRate * (1 - spread(for: holding.account))
    }

    /// Egy pozíció súlya a portfólión belül — ez a „számla megoszlása".
    func weight(for holding: Holding) -> Double {
        guard totalValueEUR > 0, let value = value(for: holding) else { return 0 }
        return (value / totalValueEUR).doubleValue
    }

    // MARK: - TBSZ fordulónapok

    /// Naptári segédek — a közös rétegben laknak, hogy a widget és az óra is
    /// ugyanazt számolja. Itt csak továbbadjuk őket.
    static func collectionYearEnd(_ year: Int) -> Date? {
        TBSZCalculator.collectionYearEnd(year)
    }

    static func tbszMilestones(collectionYear: Int) -> (threeYear: Date, fiveYear: Date)? {
        TBSZCalculator.milestones(collectionYear: collectionYear)
    }

    // MARK: - Frissítés

    /// A futó frissítés, hogy a párhuzamos hívók megvárhassák.
    private var refreshTask: Task<Void, Never>?

    /// Frissítés összevonással.
    ///
    /// Korábban egy `guard !isRefreshing else { return }` állt itt, ami NÉMÁN
    /// eldobta a második kérést. Ez import után hibát okozott: a beolvasás
    /// végén kért frissítés kimaradt, ha a főnézet frissítése épp futott, és
    /// a képernyőn nulla vagy régi értékek maradtak.
    ///
    /// - Parameter force: importnál igaz — a futó kör még a régi adatokkal
    ///   dolgozik, ezért megvárjuk, és utána indítunk egy újat.
    func refresh(force: Bool = false) async {
        if let running = refreshTask {
            await running.value
            if !force { return }
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        var failures: [String] = []

        do {
            let snapshot = try await fxService.current()
            fxRate = snapshot.eurHUF
            usdRate = snapshot.usdHUF ?? 0
            fxDate = snapshot.date
            fxSource = snapshot.source
        } catch { failures.append("EUR/HUF árfolyam") }

        for holding in holdings {
            do {
                quotes[holding.isin] = try await quoteService.quote(isin: holding.isin, ticker: holding.ticker)
            } catch {
                failures.append(holding.ticker)
            }
        }

        if !failures.isEmpty {
            lastError = "Nem sikerült frissíteni: " + failures.joined(separator: ", ")
        }

        lastRefresh = Date()
        recordSnapshotIfPossible()
        save()
    }

    /// Napi pillanatkép — naponta egy, felülírva, ha ma már volt.
    /// Csak akkor mentünk, ha MINDEN pozícióra van élő ár; a hiányos mérés
    /// hamis zuhanást rajzolna a görbére.
    private func recordSnapshotIfPossible() {
        guard !holdings.isEmpty, fxRate > 0 else { return }
        guard holdings.allSatisfy({ quotes[$0.isin] != nil }) else { return }

        let today = Calendar.current.startOfDay(for: Date())
        var perPlatform: [String: Decimal] = [:]
        for platform in resolvedPlatforms {
            perPlatform[platform.id] = valueHUF(ofPlatform: platform.id)
        }
        let snapshot = Snapshot(
            date: today,
            valueEUR: totalValueEUR,
            costEUR: totalCostEUR,
            fxRate: fxRate,
            isBackfilled: false,
            byPlatform: perPlatform
        )
        snapshots.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
        snapshots.append(snapshot)
        snapshots.sort { $0.date < $1.date }
    }

    /// Visszatölti a görbét a MAI összetétellel visszaszámolva.
    ///
    /// Ez nem a tényleges múltbeli vagyonod — az a befizetéseidtől függ, amiket
    /// az app nem ismer. Ez arra válaszol: „mennyit érne a mostani portfólióm,
    /// ha végig ez lett volna?" A sorok `isBackfilled` jelzést kapnak, és a
    /// grafikon szaggatottan rajzolja őket, hogy a kettő ne mosódjon össze.
    func backfill(range: String = "1y") async {
        guard !holdings.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var seriesByISIN: [String: [Date: Decimal]] = [:]
        for holding in holdings {
            guard let closes = try? await quoteService.dailyCloses(ticker: holding.ticker, range: range) else {
                lastError = "A visszatöltés nem sikerült (\(holding.ticker)) — a Yahoo gyakran korlátoz. Próbáld később."
                return
            }
            seriesByISIN[holding.isin] = Dictionary(
                closes.map { (Calendar.current.startOfDay(for: $0.0), $0.1) },
                uniquingKeysWith: { _, last in last }
            )
        }

        let allDays = Set(seriesByISIN.values.flatMap(\.keys)).sorted()
        guard let first = allDays.first, let last = allDays.last else { return }
        let fxSeries = (try? await fxService.rates(from: first, to: last)) ?? [:]

        let today = Calendar.current.startOfDay(for: Date())
        var rebuilt: [Snapshot] = []
        var lastKnownFX = fxRate

        for day in allDays where day < today {
            // SZÁMLÁNKÉNT döntünk teljességről, nem az egész napról. Egy
            // számla akkor kerül be, ha MINDEN papírjához van aznapi záróár
            // ÉS ismert darabszám. Ami hiányzik, az kimarad — nem nullázzuk.
            var perAccount: [String: Decimal] = [:]
            var brokenAccounts: Set<String> = []
            for holding in holdings {
                guard let close = seriesByISIN[holding.isin]?[day],
                      let quantity = quantity(of: holding, on: day) else {
                    brokenAccounts.insert(holding.account)
                    continue
                }
                perAccount[holding.account, default: 0] += quantity * close
            }
            for account in brokenAccounts { perAccount[account] = nil }
            guard !perAccount.isEmpty else { continue }
            let value = perAccount.values.reduce(Decimal(0), +)

            if let fx = fxSeries[day] { lastKnownFX = fx }
            guard lastKnownFX > 0 else { continue }

            var snapshot = Snapshot(date: day, valueEUR: value, costEUR: totalCostEUR,
                                    fxRate: lastKnownFX, isBackfilled: true)
            // Platformonként is, FORINTBAN — enélkül a kezdőképernyő közös
            // görbéje (ami platformonként rajzol) nem látja a visszatöltést,
            // és a munka eredménye sehol nem jelenik meg.
            snapshot.byPlatform = perAccount.mapValues { $0 * lastKnownFX }
            rebuilt.append(snapshot)
        }

        // ÖSSZEFÉSÜLÉS, nem csere. Egy napon állhat egyszerre mért adat (a
        // Revolut-kivonat napi egyenlege) és visszaszámolt adat (a TBSZ
        // értékpapírja) — korábban a visszaszámolt sor ilyenkor egyszerűen
        // eldobódott, ezért a TBSZ vonala a Revolut napjain nem épült fel.
        // A MÉRT adat mindig erősebb: csak a hiányzó platformokat töltjük ki.
        var byDay = Dictionary(uniqueKeysWithValues: snapshots.map {
            (Calendar.current.startOfDay(for: $0.date), $0)
        })
        for row in rebuilt {
            let day = Calendar.current.startOfDay(for: row.date)
            guard var existing = byDay[day] else { byDay[day] = row; continue }
            var injected = false
            for (id, amount) in row.byPlatform where existing.byPlatform[id] == nil {
                existing.byPlatform[id] = amount
                injected = true
            }
            if existing.valueEUR == 0 {
                existing.valueEUR = row.valueEUR
                existing.costEUR = row.costEUR
                existing.fxRate = row.fxRate
                injected = true
            }
            // Ha bármit beleszámoltunk, a sor részben rekonstruált — a
            // grafikon ezt jelzi, nem adjuk ki mérésnek.
            if injected { existing.isBackfilled = true }
            byDay[day] = existing
        }
        snapshots = byDay.values.sorted { $0.date < $1.date }
        save()
    }

    /// Hány darab volt egy adott napon.
    ///
    /// A kivonatból származó idővonal lépcsős: két ügylet között a darabszám
    /// állandó, ezért a keresett napra a LEGKÖZELEBBI KORÁBBI ügylet értéke
    /// érvényes. Ha a nap az első ügylet ELŐTTI, akkor nulla — akkor még nem
    /// volt semmid, és ezt nem szabad a mai darabszámmal kitölteni.
    /// Ha egyáltalán nincs idővonal (kézi pozíció), a mai darabszámmal
    /// számolunk; ez az a „mennyit érne a mostani portfólióm" eset, amit a
    /// felület visszaszámoltként jelöl.
    ///
    /// `nil`, ha a nap az első ISMERT ügylet ELŐTTI. Ilyenkor nem nullát
    /// adunk vissza: a nulla azt állítaná, hogy akkor nem volt semmid, pedig
    /// csak a kivonat nem ér odáig. Az a nap kimarad a görbéből.
    private func quantity(of holding: Holding, on day: Date) -> Decimal? {
        guard let timeline = quantityTimeline[holding.isin], !timeline.isEmpty else {
            return holding.quantity
        }
        let key = ConstituentWatcher.dayKey(day)
        guard let latest = timeline.keys.filter({ $0 <= key }).max() else { return nil }
        return timeline[latest]
    }

    // MARK: - Pozíciók szerkesztése

    func add(_ holding: Holding) { holdings.append(holding); save() }

    /// Beolvas egy Lightyear számlakivonatot, és **összefésüli** a meglévő
    /// adatokkal: csak az adott SZÁMLÁHOZ tartozó tételeket cseréli le.
    ///
    /// Miért nem egyszerű felülírás: 2027-ben új TBSZ-t nyitsz, és onnantól két
    /// külön kivonatod lesz. Ugyanaz az alap (VWCE) állhat mindkettőben, más
    /// gyűjtőévvel és más bekerülési árral — ezért az (ISIN, számla) pár a
    /// kulcs, nem az ISIN önmagában. Felülírásnál a második import kitörölné
    /// az elsőt.
    ///
    /// Visszaadja a figyelmeztetéseket és a felismert számla azonosítóját.
    func importStatement(from url: URL, tbszYear: Int) async throws -> (warnings: [String], account: String) {
        // A fájlválasztóból jövő URL biztonsági hatókörű: enélkül nem olvasható.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)

        // PDF-ből kiolvassuk a szövegréteget, és onnantól ugyanúgy bánunk
        // vele, mint egy CSV-vel: a formátumot a TARTALOM dönti el.
        let text: String
        if PDFStatement.looksLikePDF(data) {
            text = try PDFStatement.text(from: data)
        } else if let plain = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin2) {
            text = plain
        } else {
            throw StatementImporter.ImportError.notText(Self.describe(data, url: url))
        }

        // A számlaazonosító a fájlnévből jön; ha nincs benne, a fájlnév maga.
        let fileName = url.deletingPathExtension().lastPathComponent

        // Formátum-felismerés a FEJLÉC alapján, nem a fájlnévből: háromféle
        // kivonatot fogadunk (Lightyear, Revolut megtakarítás, Revolut
        // folyószámla), és mindegyik más szerkezetű.
        if let kind = RevolutImporter.detect(csv: text) {
            return applyRevolut(kind: kind, text: text)
        }
        if OTPImporter.detect(text: text) != nil {
            return try applyOTP(text: text)
        }
        if StateTreasuryImporter.detect(text: text) {
            return try applyStateTreasury(text: text, accountHint: fileName)
        }

        let account = StatementImporter.accountReference(from: fileName) ?? fileName

        // A már ismert gyűjtőév, ha volt korábbi import erről a számláról.
        // A gyűjtőév a TBSZ ELSŐ befizetésének éve — egy később exportált,
        // szűkebb időszakú kivonatban ez a nap már nem szerepel, és a beolvasó
        // tévesen egy későbbi évet számolna. Ezért csak korábbra engedjük mozdulni.
        let knownYear = holdings.filter { $0.account == account }.map(\.tbszYear).min()

        let result = try await StatementImporter().import(csv: text, account: account, tbszYear: tbszYear)

        // Csak ennek a számlának a tételeit dobjuk el, a többit érintetlenül hagyjuk.
        holdings.removeAll { $0.account == account }
        deposits.removeAll { $0.account == account }
        fees.removeAll { $0.account == account }

        // Csak ENNEK a számlának az adatát cseréljük — a többi marad.
        cash[account] = result.cash
        conversionSpread[account] = result.conversionSpread

        holdings.append(contentsOf: result.holdings.map { holding in
            guard let knownYear else { return holding }
            var adjusted = holding
            adjusted.tbszYear = min(knownYear, holding.tbszYear)
            return adjusted
        })
        deposits.append(contentsOf: result.deposits)
        fees.append(contentsOf: result.fees)

        // A kivonatból visszaszámolt görbepontok és ügyletjelölők.
        mergeHistory(platformID: account, daily: result.dailyValues)
        trades.removeAll { $0.platform == account }
        trades.append(contentsOf: result.trades)

        // A darabszám-idővonal ÖSSZEFÉSÜLŐDIK, nem cserélődik: egy szűkebb
        // időszakú újabb kivonat nem törölheti a régebbi napok darabszámát.
        for (isin, byDay) in result.quantityByDay {
            for (day, quantity) in byDay {
                quantityTimeline[isin, default: [:]][ConstituentWatcher.dayKey(day)] = quantity
            }
        }

        holdings.sort { ($0.account, $0.ticker) < ($1.account, $1.ticker) }
        deposits.sort { $0.date < $1.date }
        fees.sort { $0.date < $1.date }

        save()
        await refresh(force: true)
        return (result.warnings, account)
    }

    /// Államkincstári portfólió-export beolvasása.
    ///
    /// A MÁK-kivonatok nem illeszthetők be árfolyam-alapú `Holding` modellbe,
    /// mert az állampapír-értékhez nincs támogatott árfolyamforrás.
    /// Ezért a platformot készpénz-eszközként importáljuk friss HUF egyenleggel,
    /// így minden képernyőben megjelenik a vagyonkészletben és a platform-kártyákon.
    private func applyStateTreasury(text: String, accountHint: String) throws
        -> (warnings: [String], account: String) {
        let result = try StateTreasuryImporter.import(text: text, accountHint: accountHint)

        cashAssets.removeAll { $0.platform == result.platformID }
        deposits.removeAll { $0.account == result.platformID }
        upsertKind(.savings, id: result.platformID, name: result.accountName, monogram: "AK")

        cashAssets.append(result.asset)
        save()

        return (result.warnings, result.accountName)
    }

    /// Mi ez a fájl, ha nem szöveg. A tartalom ELSŐ BÁJTJAIBÓL, nem a
    /// kiterjesztésből: a megosztólapról átnevezett fájl is érkezhet.
    private static func describe(_ data: Data, url: URL) -> String {
        let head = data.prefix(8)
        if head.starts(with: Array("%PDF".utf8)) { return "egy PDF" }
        if head.starts(with: [0x50, 0x4B]) { return "egy tömörített fájl (XLSX vagy ZIP)" }
        if head.starts(with: [0xD0, 0xCF]) { return "egy régi Excel-fájl (XLS)" }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "ismeretlen formátumú fájl" : "egy \(ext) fájl"
    }

    /// Indulási sorrend: előbb a megosztólapról érkezett fájlok, aztán a
    /// frissítés — fordítva a beolvasás eredménye nem látszana azonnal.
    @discardableResult
    func startup() async -> [String] {
        let report = await processInbox()
        await refresh()
        return report
    }

    /// Feldolgozza a megosztólapról érkezett fájlokat.
    ///
    /// A kiterjesztés csak leteszi a fájlt; a beolvasás itt történik, mert
    /// ahhoz hálózat kell (devizatörténet a forintos bekerülési értékhez).
    /// Hibás fájlt is eltávolítunk a postaládából — különben minden induláskor
    /// újra megpróbálná és újra hibát mutatna. Az eredeti fájl megvan neked.
    func processInbox() async -> [String] {
        var report: [String] = []
        // Előbb behozzuk, amit az iCloud-mappába tettél (akár Macről),
        // aztán átnézzük a kijelölt mappáidat (pl. az iCloud Drive gyökerét).
        Inbox.collectFromCloud()
        WatchedFolders.collect()
        let year = Calendar.current.component(.year, from: Date())
        for url in Inbox.pending() {
            do {
                let (warnings, account) = try await importStatement(from: url, tbszYear: year)
                report.append("\(url.lastPathComponent) → \(account)")
                report.append(contentsOf: warnings)
            } catch {
                report.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
            Inbox.remove(url)
        }
        return report
    }

    /// Beépíti a kivonatból kiolvasott NAPI egyenlegeket a mérési előzménybe.
    ///
    /// A Revolut minden sorhoz kiírja az egyenleget, tehát a teljes időszak
    /// görbéje benne van a fájlban — kár lenne megvárni, hogy az app napról
    /// napra összemérje. A meglévő napokat kiegészítjük, a hiányzókat
    /// létrehozzuk; a többi platform aznapi értékéhez nem nyúlunk.
    private func mergeHistory(platformID: String, daily: [Date: Decimal]) {
        guard !daily.isEmpty else { return }
        var byDay = Dictionary(uniqueKeysWithValues: snapshots.map {
            (Calendar.current.startOfDay(for: $0.date), $0)
        })

        for (rawDate, value) in daily {
            let day = Calendar.current.startOfDay(for: rawDate)
            if var existing = byDay[day] {
                existing.byPlatform[platformID] = value
                byDay[day] = existing
            } else {
                // Új nap: csak ennek a platformnak az értékét ismerjük.
                // Az értékpapír-mezők nullák maradnak — azokra nincs adatunk
                // visszamenőleg, és kitalálni tilos.
                var fresh = Snapshot(date: day, valueEUR: 0, costEUR: 0, fxRate: 0)
                fresh.byPlatform[platformID] = value
                byDay[day] = fresh
            }
        }
        snapshots = byDay.values.sorted { $0.date < $1.date }
    }

    /// Van-e olyan megtakarítás, aminek az egyenlege becsléssel gördül?
    /// A felület ezt jelzi, hogy a szám ne látszódjon mérésnek.
    var hasEstimatedBalances: Bool {
        cashAssets.contains { $0.netDailyRate != nil && $0.daysSinceStatement() > 0 }
    }

    /// A becsléssel hozzáírt kamat összesen — ennyivel tér el a kijelzett
    /// vagyon a legutóbbi kivonatok szerinti állapottól.
    var estimatedInterestHUF: Decimal {
        cashAssets.reduce(Decimal(0)) {
            $0 + convertToHUF($1.estimatedInterest(), currency: $1.currency)
        }
    }

    /// A legrégebbi becslés kora napokban — ebből tudja a felület, mikor
    /// érdemes szólni, hogy ideje új kivonatot beolvasni.
    var oldestEstimateDays: Int? {
        cashAssets.compactMap { $0.netDailyRate != nil ? $0.daysSinceStatement() : nil }.max()
    }

    /// Az órának küldött összefoglaló. Csak számok — az óra nem számol.
    var watchSummary: WatchSummary {
        var summary = WatchSummary()
        summary.totalHUF = grandTotalHUF
        summary.gainHUF = grandGainHUF
        summary.gainPct = grandGainPct
        summary.asOf = lastRefresh
        summary.rows = platformSummaries.map { item in
            WatchSummary.Row(
                id: item.platform.id,
                name: item.platform.name,
                monogram: item.platform.monogram,
                accent: item.platform.accent.rawValue,
                valueHUF: item.valueHUF,
                gainPct: item.gainPct
            )
        }
        summary.spark = snapshots.suffix(30).map { ($0.valueEUR * $0.fxRate).doubleValue }
        // Az órára csak az az időszak megy fel, aminek a százaléka jelent
        // valamit. A telefonon a „nincs értelmes alap" esetet ki tudjuk írni,
        // egy 25 mm-es kijelzőn nem — ott a félreérthető szám rosszabb, mint
        // a hiányzó.
        summary.periods = periodChanges.filter(\.isPercentMeaningful).map {
            WatchSummary.Period(id: $0.span.rawValue, title: $0.span.title,
                                pct: $0.pct, gainHUF: $0.gainHUF)
        }
        return summary
    }

    /// Az OTP-kivonatok alkalmazása.
    ///
    /// A folyószámla készpénz-eszközként kerül be (mint a Revolut
    /// folyószámla), a hitelkártya pedig KÖTELEZETTSÉGKÉNT: negatív értékkel,
    /// hogy a nettó vagyonból levonódjon. Egy tartozást pozitív egyenlegként
    /// beírni hamis vagyont mutatna.
    ///
    /// Mindkettőből kiadási tételek is készülnek — azokból épül a Kiadások fül.
    private func applyOTP(text: String) throws -> (warnings: [String], account: String) {
        let result = try OTPImporter.import(text: text)
        let id = result.kind == .credit ? "otp-hitelkartya" : "otp-folyoszamla"
        let name = result.kind == .credit ? "OTP Hitelkártya" : "OTP Folyószámla"

        // A tételek MINDIG frissülnek: az azonosító stabil, tehát az azonos
        // tételt a második import felismeri és nem duplázza.
        var byID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
        for entry in result.entries {
            let merchant = ExpenseCategorizer.merchant(from: entry.text)
            let key = ExpenseEntry.makeID(account: id, date: entry.date,
                                          amount: entry.amountHUF, text: entry.text)
            // A KÉZI átsorolást nem írjuk felül: az erősebb a szabálynál.
            if let existing = byID[key], existing.manualCategory { continue }
            byID[key] = ExpenseEntry(
                id: key, date: entry.date, amountHUF: entry.amountHUF,
                merchant: merchant,
                category: ExpenseCategorizer.categorize(entry.text),
                account: id
            )
        }
        expenses = byID.values.sorted { $0.date > $1.date }

        if result.kind == .credit {
            // A tartozás NEGATÍV eszközként. A `closing` már negatív a
            // kivonatban (−650 867), tehát pont jó előjellel jön.
            cashAssets.removeAll { $0.platform == id }
            cashAssets.append(CashAsset(platform: id, name: name,
                                        balance: result.closing,
                                        currency: result.currency,
                                        annualRatePct: nil, asOf: statementDate(result)))
            upsertKind(.credit, id: id, name: name, monogram: "HK")
            // A fizetési adatok: ezekből lesz az emlékeztető.
            creditCards.removeAll { $0.platform == id }
            creditCards.append(CreditCardStatus(
                platform: id,
                totalDebt: result.totalDebt ?? abs(result.closing),
                minimumPayment: result.minimumPayment,
                dueDate: result.dueDate,
                creditLimit: result.creditLimit,
                asOf: statementDate(result)))
            let card = creditCards.last
            Task { await PaymentReminder.schedule(for: card) }
        } else {
            cashAssets.removeAll { $0.platform == id }
            cashAssets.append(CashAsset(platform: id, name: name,
                                        balance: result.closing,
                                        currency: result.currency,
                                        annualRatePct: nil, asOf: statementDate(result)))
            // A folyószámlán álló pénz nem „hozam": a befizetés annyi,
            // amennyi rajta van, tehát a hozama pontosan nulla.
            //
            // De NEM egyetlen összegként vezetjük be. Egy lump-befizetés a
            // kivonat dátumára fantom pénzbeáramlást csinál: a havi eredmény
            // −32%-ot mutatott attól, hogy a számla bekerült. A valódi
            // tételekből képezzük, mindegyiket a SAJÁT napjával — így az
            // időszak-számítás ki tudja vonni őket, és a hozam végig nulla.
            deposits.removeAll { $0.account == id }
            if let first = result.entries.map(\.date).min() {
                deposits.append(Deposit(account: id, date: first,
                                        amountHUF: result.opening, isInternal: false))
            }
            for entry in result.entries {
                deposits.append(Deposit(account: id, date: entry.date,
                                        amountHUF: entry.amountHUF, isInternal: false))
            }
            upsertKind(.current, id: id, name: name, monogram: "OF")
            mergeHistory(platformID: id, daily: result.dailyBalances)
        }

        save()
        var warnings = result.warnings
        warnings.append("\(result.entries.count) tétel beolvasva, \(expenses.filter { $0.account == id }.count) van összesen ezen a számlán.")
        return (warnings, name)
    }

    private func statementDate(_ result: OTPImporter.Result) -> Date {
        result.entries.map(\.date).max() ?? Date()
    }

    /// Az Enable Banking élő számlaadatait beolvasztja ugyanabba a modellbe,
    /// amelyet a kivonat-importok is használnak. A kézzel átsorolt kiadások
    /// itt is érintetlenek maradnak, az azonos tranzakció pedig nem duplázódik.
    func applyEnableBanking(_ result: EBSyncResult) {
        var byID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
        let bank = ExpenseCategorizer.normalize(result.bankName)
        let otp = bank.contains("OTP")
        let revolut = bank.contains("REVOLUT")

        for (index, synced) in result.accounts.enumerated() {
            let account = synced.details
            guard let uid = account.uid else { continue }
            let isCredit = ["CARD", "CRDT"].contains(account.cashAccountType.uppercased())
            let platformID: String
            if otp && index == 0 {
                platformID = isCredit ? "otp-hitelkartya" : "otp-folyoszamla"
            } else if revolut && index == 0 && !isCredit {
                // Ugyanaz a megfontolás, mint az OTP-nél: a bankkapcsolatból
                // jövő folyószámla KAPJA MEG a kivonatból ismert azonosítót,
                // különben ugyanaz a számla kétszer szerepelne — egyszer a
                // kivonatból, egyszer a bankkapcsolatból. A két forrás így
                // összeolvad, és a frissebb adat írja felül a régebbit.
                platformID = "revolut-account"
            } else {
                platformID = "enable-banking-\(uid.lowercased())"
            }

            let suffix = account.iban.map { " · •••• \($0.suffix(4))" } ?? ""
            let baseName = account.details ?? account.product ?? account.displayName
            let name = "\(result.bankName) · \(baseName)\(suffix)"

            if let current = preferredBalance(synced.balances) {
                var amount = current.balanceAmount.amount
                if isCredit { amount = -abs(amount) }
                cashAssets.removeAll { $0.platform == platformID }
                cashAssets.append(CashAsset(
                    platform: platformID,
                    name: name,
                    balance: amount,
                    currency: current.balanceAmount.currency,
                    annualRatePct: nil,
                    asOf: enableBankingDate(current.referenceDate) ?? result.syncedAt
                ))
                // A PSD2 csak FIZETÉSI számlát tesz elérhetővé — megtakarítási
                // számlát nem (ezt mértük: a Revolut Savingset és az OTP
                // hitelkártyát nem is lehetett hozzáadni). Ami tehát innen
                // jön és nem hitel, az folyószámla.
                upsertKind(isCredit ? .credit : .current,
                           id: platformID, name: name,
                           monogram: isCredit ? "HK" : Platform.defaultMonogram(for: result.bankName))
                bankLinkedPlatforms[platformID] = result.bankName
            }

            for transaction in synced.transactions where transaction.status == "BOOK" {
                guard let date = enableBankingDate(
                    transaction.bookingDate ?? transaction.valueDate ?? transaction.transactionDate
                ) else { continue }
                let raw = transaction.creditDebitIndicator == "CRDT"
                    ? transaction.transactionAmount.amount
                    : -transaction.transactionAmount.amount
                let amountHUF = convertToHUF(raw, currency: transaction.transactionAmount.currency)
                let text = transaction.description.isEmpty ? "Banki tranzakció" : transaction.description
                let key = transaction.transactionID.map { "eb|\(platformID)|\($0)" }
                    ?? ExpenseEntry.makeID(account: platformID, date: date,
                                           amount: amountHUF, text: text)
                if let existing = byID[key], existing.manualCategory { continue }
                byID[key] = ExpenseEntry(
                    id: key,
                    date: date,
                    amountHUF: amountHUF,
                    merchant: ExpenseCategorizer.merchant(from: text),
                    category: ExpenseCategorizer.categorize(text),
                    account: platformID
                )
            }
        }

        cashAssets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        expenses = byID.values.sorted { $0.date > $1.date }
        save()
    }

    private func preferredBalance(_ balances: [EBBalance]) -> EBBalance? {
        let priority = ["CLAV", "CLBD", "ITAV", "ITBD", "XPCD", "OPAV", "PRCD"]
        return balances.min {
            (priority.firstIndex(of: $0.balanceType ?? "") ?? priority.count)
                < (priority.firstIndex(of: $1.balanceType ?? "") ?? priority.count)
        }
    }

    private func enableBankingDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        if let parsed = day.date(from: value) { return parsed }
        return ISO8601DateFormatter().date(from: value)
    }

    /// Létrehozza a platformot, vagy HELYESBÍTI a típusát.
    ///
    /// A nevet és a színt nem írjuk felül — azokat te szabhatod testre. A
    /// TÍPUS viszont nem ízlés kérdése: ha egy hitelkártya korábban
    /// megtakarításként került be, az számítási hiba, és minden hozamot
    /// elront. Mérve: a −650 867 Ft tartozás −44,66%-os „hozamként" jelent meg.
    /// A folyószámlák korábban `savings` besorolással készültek, mert nem
    /// volt külön típusuk. Aki nem olvas be újra kivonatot, annál ez ott
    /// ragadna, és a hozam továbbra is a fizetését mutatná eredménynek.
    /// Ezért egyszer, betöltéskor átsoroljuk őket.
    private func migrateCurrentAccountKinds() {
        let known: Set<String> = ["otp-folyoszamla", "revolut-account"]
        var changed = false
        for index in platforms.indices where platforms[index].kind == .savings {
            let id = platforms[index].id
            // Amit a bankkapcsolat hozott és nem hitel, az fizetési számla.
            let fromBank = bankLinkedPlatforms[id] != nil
            guard known.contains(id) || fromBank else { continue }
            platforms[index].kind = .current
            changed = true
        }
        if changed { save() }
    }

    private func upsertKind(_ kind: Platform.Kind, id: String, name: String,
                            monogram: String) {
        if let index = platforms.firstIndex(where: { $0.id == id }) {
            if platforms[index].kind != kind { platforms[index].kind = kind }
        } else {
            platforms.append(Platform(id: id, name: name, kind: kind,
                                      accent: freeAccent(), monogram: monogram))
        }
    }

    private func freeAccent() -> Platform.Accent {
        let used = Set(platforms.map(\.accent))
        return Platform.Accent.allCases.first { !used.contains($0) } ?? .lilac
    }

    /// A Revolut-kivonatok alkalmazása. Számlánként cserél, mint a Lightyearnél.
    private func applyRevolut(kind: RevolutImporter.Kind, text: String)
        -> (warnings: [String], account: String) {
        let id = kind == .savings ? "revolut-savings" : "revolut-account"
        let result = kind == .savings
            ? RevolutImporter.importSavings(csv: text, platformID: id)
            : RevolutImporter.importAccount(csv: text, platformID: id)

        deposits.removeAll { $0.account == id }
        fees.removeAll { $0.account == id }
        cashAssets.removeAll { $0.platform == id }

        deposits.append(contentsOf: result.deposits)
        fees.append(contentsOf: result.fees)
        cashAssets.append(result.asset)

        // A platform NEVÉT és SZÍNÉT nem írjuk felül, ha már testre szabtad.
        if !platforms.contains(where: { $0.id == id }) {
            platforms.append(result.platform)
        }

        deposits.sort { $0.date < $1.date }
        fees.sort { $0.date < $1.date }
        mergeHistory(platformID: id, daily: result.dailyBalances)
        save()

        var warnings = result.warnings
        if !result.dailyBalances.isEmpty {
            warnings.append("\(result.dailyBalances.count) napi egyenleg a kivonatból — a görbe visszamenőleg is megvan.")
        }
        return (warnings, result.platform.name)
    }

    /// Hány külön számláról van adat. Egynél többnél a felület kiírja,
    /// melyik pozíció melyikhez tartozik.
    var accounts: [String] {
        Array(Set(holdings.map(\.account))).sorted()
    }

    /// Elmenti (vagy frissíti) egy platform beállításait — név, típus, szín.
    /// A TBSZ adókulcsai. Ha nincs mentve, a gyűjtőév szerinti alapérték.
    func rules(forCollectionYear year: Int) -> TBSZRules {
        tbszRules ?? TBSZRules.suggested(forCollectionYear: year)
    }

    func setTBSZRules(_ rules: TBSZRules) { tbszRules = rules; save() }

    func setScenario(_ value: Scenario) { scenario = value; save() }

    /// Kövesse-e az app ikonja a témát. Alapból KI: az ikoncsere iOS-en
    /// rendszerszintű értesítést dob fel („Megváltoztattad az ikont"), amit
    /// nem lehet elnyomni — témánként egyet látni nem kellemes, ezért ez
    /// külön kapcsoló.
    var iconFollowsTheme: Bool {
        get { UserDefaults.standard.bool(forKey: "iconFollowsTheme") }
        set {
            UserDefaults.standard.set(newValue, forKey: "iconFollowsTheme")
            applyIcon(newValue ? AppTheme.named(themeID) : nil)
        }
    }

    /// Kézi átsorolás. A jelölés miatt az újraimport nem írja felül.
    func recategorize(_ entry: ExpenseEntry, to category: ExpenseCategory) {
        guard let index = expenses.firstIndex(where: { $0.id == entry.id }) else { return }
        expenses[index].category = category
        expenses[index].manualCategory = true
        save()
    }

    func hideNews(_ link: String) { hiddenNews.insert(link); save() }
    func unhideNews(_ link: String) { hiddenNews.remove(link); save() }

    func setTheme(_ theme: AppTheme) {
        themeID = theme.id
        DS.Color.theme = theme
        if iconFollowsTheme { applyIcon(theme) }
        save()
    }

    /// `nil` = vissza az alapikonra.
    private func applyIcon(_ theme: AppTheme?) {
        let name = theme.map { "AppIcon-\($0.id)" }
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error { print("ikoncsere: \(error.localizedDescription)") }
        }
    }

    /// Alapértelmezett célidőpont: a legkorábbi TBSZ 5 éves lejárata — annál a
    /// dátumnál lesz adómentes, tehát az a valódi tervezési horizont.
    var defaultScenarioTarget: Date {
        let years = resolvedPlatforms.compactMap(\.tbszYear)
        if let earliest = years.min(),
           let five = TBSZCalculator.milestones(collectionYear: earliest)?.fiveYear {
            return five
        }
        return Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
    }

    func upsertPlatform(_ platform: Platform) {
        if let index = platforms.firstIndex(where: { $0.id == platform.id }) {
            platforms[index] = platform
        } else {
            platforms.append(platform)
        }
        save()
    }

    /// Kamatozó készpénz-eszköz (pl. Revolut Savings) felvétele vagy módosítása.
    func upsertCashAsset(_ asset: CashAsset) {
        if let index = cashAssets.firstIndex(where: { $0.id == asset.id }) {
            cashAssets[index] = asset
        } else {
            cashAssets.append(asset)
        }
        // Ha még nincs platformja, hozzunk létre egyet, hogy megjelenjen a listán.
        if !platforms.contains(where: { $0.id == asset.platform }) {
            let used = Set(platforms.map(\.accent))
            let accent = Platform.Accent.allCases.first { !used.contains($0) } ?? .lilac
            platforms.append(Platform(id: asset.platform, name: asset.name,
                                      kind: .savings, accent: accent))
        }
        save()
    }

    func deleteCashAsset(_ asset: CashAsset) {
        cashAssets.removeAll { $0.id == asset.id }
        save()
    }

    func removeAccount(_ account: String) {
        holdings.removeAll { $0.account == account }
        deposits.removeAll { $0.account == account }
        fees.removeAll { $0.account == account }
        // A kiadás-tételek is ehhez a számlához tartoznak: enélkül a törölt
        // számla költései a Kiadások fülön ott maradnának, gazdátlanul.
        expenses.removeAll { $0.account == account }
        cashAssets.removeAll { $0.platform == account }
        platforms.removeAll { $0.id == account }
        cash[account] = nil
        conversionSpread[account] = nil
        save()
    }

    func update(_ holding: Holding) {
        guard let index = holdings.firstIndex(where: { $0.id == holding.id }) else { return }
        holdings[index] = holding
        save()
    }

    func delete(at offsets: IndexSet) {
        holdings.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Tárolás

    func load() {
        let (payload, status) = PortfolioFile.loadDetailed()

        switch status {
        case .ok, .missing:
            hasLoaded = true
        case .recovered:
            hasLoaded = true
            lastError = "A tárolt állomány sérült volt, a biztonsági másolatból állt vissza."
        case .corrupt:
            // NEM engedünk mentést: a fájl létezik, csak nem tudjuk elolvasni.
            // Ha most írnánk, végleg felülírnánk a benne lévő adatot.
            hasLoaded = false
            lastError = "A tárolt adatot nem sikerült elolvasni. Amíg ez így van, az app nem ír a fájlra, hogy ne vesszen el. Olvasd be újra a kivonatot."
            return
        }
        holdings = payload.holdings
        snapshots = payload.snapshots.sorted { $0.date < $1.date }
        deposits = payload.deposits.sorted { $0.date < $1.date }
        fees = payload.fees.sorted { $0.date < $1.date }
        platforms = payload.platforms
        cashAssets = payload.cashAssets
        cash = payload.cash
        conversionSpread = payload.conversionSpread
        tbszRules = payload.tbszRules
        trades = payload.trades
        platformOrder = payload.platformOrder
        bankLinkedPlatforms = payload.bankLinkedPlatforms
        mutationCount &+= 1
        migrateCurrentAccountKinds()
        quantityTimeline = payload.quantityTimeline
        hiddenNews = Set(payload.hiddenNews)
        expenses = payload.expenses
        creditCards = payload.creditCards
        allocationTargets = payload.allocationTargets
        themeID = payload.themeID
        // A dizájnrendszer globálisan olvassa az aktív témát; a nézetek csak
        // szerepeket kérnek, ezért itt elég egyszer beállítani.
        DS.Color.theme = AppTheme.named(payload.themeID)
        scenario = payload.scenario
        lastRefresh = payload.lastRefresh
        // Az utolsó ismert árakkal azonnal van mit mutatni, még a hálózat előtt.
        fxRate = payload.fxRate
        for holding in holdings {
            if let price = payload.lastPrices[holding.isin] {
                quotes[holding.isin] = Quote(isin: holding.isin, price: price,
                                             changePercent: 0,
                                             timestamp: payload.lastRefresh ?? .distantPast)
            }
        }
    }

    func save() {
        mutationCount &+= 1
        // Soha nem írunk olyan állapotot, amit nem előztünk meg olvasással.
        // Ez az utolsó védvonal: ha bármelyik jövőbeli útvonal betöltés előtt
        // módosítana és mentene, itt megáll, ahelyett hogy kiürítené a fájlt.
        guard hasLoaded else { return }

        var payload = PortfolioFile.Payload()
        payload.holdings = holdings
        payload.snapshots = snapshots
        payload.deposits = deposits
        payload.fees = fees
        payload.platforms = platforms
        payload.cashAssets = cashAssets
        payload.cash = cash
        payload.conversionSpread = conversionSpread
        payload.tbszRules = tbszRules
        payload.trades = trades
        payload.platformOrder = platformOrder
        payload.bankLinkedPlatforms = bankLinkedPlatforms
        payload.quantityTimeline = quantityTimeline
        payload.hiddenNews = Array(hiddenNews)
        payload.expenses = expenses
        payload.creditCards = creditCards
        payload.allocationTargets = allocationTargets
        payload.themeID = themeID
        payload.scenario = scenario
        payload.lastRefresh = lastRefresh
        payload.fxRate = fxRate
        payload.lastPrices = quotes.mapValues(\.price)
        PortfolioFile.save(payload)
        if BackupSecurityManager.isEnabled {
            try? BackupSecurityManager.save(payload)
        }
        // A widget külön folyamat — magától nem tudja, hogy változott az adat.
        WidgetCenter.shared.reloadAllTimelines()
        // Az óra pedig külön ESZKÖZ: neki külön kell átküldeni.
        WatchBridge.shared.send(watchSummary)
    }
}
