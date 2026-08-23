import Foundation
import WidgetKit

/// Egy PLATFORM a widgeten — nem egy értékpapír.
///
/// Korábban a pozíciókból készült, ezért egyetlen ETF-fel a widget „VWCE
/// 100%"-ot mutatott, míg az app három platformot. Ugyanaz a portfólió, két
/// különböző igazság.
struct PortfolioSlice: Identifiable {
    let id: String
    /// A platform TELJES neve. Korábban a monogram állt itt (`T2`, `RS`), de
    /// az kód, nem név: a widgetről ránézésre nem lehetett megmondani, melyik
    /// számláról van szó. Ami nem fér ki, azt a nézet kicsinyíti.
    let name: String
    /// A platform akcentusának sorszáma. Enélkül a widgeten minden sáv
    /// ugyanaz a szín volt, és a sávok nem jelentettek semmit.
    let accentIndex: Int
    let weight: Double
    let valueHUF: Decimal
    let gainPercent: Double
}

struct PortfolioEntry: TimelineEntry {
    var date: Date = Date()
    var valueEUR: Decimal = 0
    var costEUR: Decimal = 0
    var fxRate: Decimal = 0
    var dayChangeEUR: Decimal?
    var slices: [PortfolioSlice] = []
    /// Napi ÖSSZVAGYON a szikragörbéhez, FORINTBAN — ugyanaz a sorozat,
    /// amiből a kezdőképernyő közös görbéje épül. Korábban az értékpapírok
    /// eurós értéke volt, ezért nézett ki más alakúnak, mint az appban.
    var sparkline: [Double] = []
    /// A forintban realizálható teljes érték (árréssel, készpénzzel,
    /// megtakarításokkal) — ugyanaz a szám, amit az app fejléce mutat.
    var netHUF: Decimal = 0
    /// Összes befizetés — a „kezdetektől" hozam alapja, ahogy a brókernél is.
    var depositsHUF: Decimal = 0

    /// Igaz, ha ezt a bejegyzést friss hálózati lekérés töltötte fel.
    /// Hamis = az app utolsó mentéséből olvastuk.
    var isLive: Bool = true
    var asOf: Date?
    var hasHoldings: Bool = true

    var valueHUF: Decimal { netHUF > 0 ? netHUF : valueEUR * fxRate }
    var gainEUR: Decimal { valueEUR - costEUR }

    /// Hozam a befizetésekhez mérve — a brókerrel egyező mérce.
    var gainVsDeposits: Decimal? {
        guard depositsHUF > 0, netHUF > 0 else { return nil }
        return netHUF - depositsHUF
    }
    var gainVsDepositsPct: Double? {
        guard let gain = gainVsDeposits, depositsHUF > 0 else { return nil }
        return (gain / depositsHUF).doubleValue * 100
    }
    /// Amit a widget kiír: elsősorban a befizetésekhez mért hozam (ez egyezik
    /// a brókerrel), és csak ha az nincs, akkor az eszközszintű.
    var displayGainPct: Double { gainVsDepositsPct ?? gainPercent }

    var gainPercent: Double {
        guard costEUR > 0 else { return 0 }
        return ((valueEUR - costEUR) / costEUR).doubleValue * 100
    }

    static let placeholder: PortfolioEntry = {
        var e = PortfolioEntry()
        e.valueEUR = 2_032; e.costEUR = 2_038; e.fxRate = 365.1
        e.netHUF = 887_909; e.depositsHUF = 875_800
        e.dayChangeEUR = 142
        e.slices = [
            .init(id: "a", name: "TBSZ 2026", accentIndex: 0,
                  weight: 0.62, valueHUF: 550_500, gainPercent: 0.9),
            .init(id: "b", name: "Revolut Savings", accentIndex: 1,
                  weight: 0.35, valueHUF: 310_400, gainPercent: 0.1),
            .init(id: "c", name: "Revolut", accentIndex: 2,
                  weight: 0.03, valueHUF: 27_009, gainPercent: 0),
        ]
        e.sparkline = [845_000, 852_000, 849_000, 861_000, 858_000, 872_000, 881_000, 887_909]
        return e
    }()

    /// Összeállít egy bejegyzést: elsőként élő árfolyammal próbálkozik, és ha
    /// az nem megy (repülőgép mód, rate limit, lejárt widget-büdzsé), akkor az
    /// app által utoljára mentett árakkal számol — de `isLive = false` jelzéssel,
    /// hogy a widget ne tegyen úgy, mintha friss adatot mutatna.
    static func make() async -> PortfolioEntry {
        let payload = PortfolioFile.load()
        guard !payload.holdings.isEmpty else {
            var empty = PortfolioEntry()
            empty.hasHoldings = false
            return empty
        }

        var prices = payload.lastPrices
        var fx = payload.fxRate
        var isLive = true

        let quoteService = QuoteService()
        for holding in payload.holdings {
            if let quote = try? await quoteService.quote(isin: holding.isin, ticker: holding.ticker) {
                prices[holding.isin] = quote.price
            } else {
                isLive = false
            }
        }
        if let rate = try? await FXService().currentRate() { fx = rate } else { isLive = false }

        // Hiányzó ár esetén inkább a mentett állapotot mutatjuk, mint egy
        // hiányos — tehát hamisan alacsony — összeget.
        guard payload.holdings.allSatisfy({ prices[$0.isin] != nil }), fx > 0 else {
            var stale = PortfolioEntry()
            stale.hasHoldings = true
            stale.isLive = false
            stale.asOf = payload.lastRefresh
            if let last = payload.snapshots.last {
                stale.valueEUR = last.valueEUR
                stale.costEUR = last.costEUR
                stale.fxRate = last.fxRate
            }
            stale.sparkline = PortfolioMath.dailyTotalsHUF(payload)
            return stale
        }

        // MINDEN szám a közös `PortfolioMath`-ból. A widgetnek nincs saját
        // matekja: korábban volt, és emiatt más portfóliót mutatott, mint az app.
        let live = PortfolioMath.Prices(quotes: prices, fxRate: fx, usdRate: 0)
        let total = payload.holdings.reduce(Decimal(0)) { $0 + $1.quantity * (prices[$1.isin] ?? 0) }
        let cost = payload.holdings.reduce(Decimal(0)) { $0 + $1.costBasis }

        let platforms = PortfolioMath.resolvedPlatforms(payload)
        var perPlatform: [String: Decimal] = [:]
        for platform in platforms {
            perPlatform[platform.id] = PortfolioMath.valueHUF(ofPlatform: platform.id,
                                                             in: payload, prices: live)
        }
        let netHUF = perPlatform.values.reduce(Decimal(0), +)

        var entry = PortfolioEntry()
        entry.netHUF = netHUF
        // A belső átvezetések NEM új pénz — ugyanaz a szabály, mint az appban.
        // Nyersen összeadva a befizetést a hozam hamisan romlana.
        entry.depositsHUF = PortfolioMath.depositsHUF(payload)
        entry.valueEUR = total
        entry.costEUR = cost
        entry.fxRate = fx
        entry.isLive = isLive
        entry.asOf = isLive ? Date() : payload.lastRefresh
        entry.slices = platforms.compactMap { platform -> PortfolioSlice? in
            let value = perPlatform[platform.id] ?? 0
            guard value > 0 else { return nil }
            let deposits = PortfolioMath.depositsHUF(ofPlatform: platform.id, in: payload)
            return PortfolioSlice(
                id: platform.id,
                name: platform.name,
                accentIndex: platform.accent.index,
                weight: netHUF > 0 ? (value / netHUF).doubleValue : 0,
                valueHUF: value,
                gainPercent: deposits > 0 ? ((value - deposits) / deposits).doubleValue * 100 : 0
            )
        }
        .sorted { $0.weight > $1.weight }

        let today = Calendar.current.startOfDay(for: Date())
        if let previous = payload.snapshots.filter({ $0.date < today }).max(by: { $0.date < $1.date }) {
            entry.dayChangeEUR = total - previous.valueEUR
        }

        // A widget MENTI is a napi mérést, nem csak megjeleníti.
        // Enélkül a görbe csak akkor nőne, ha megnyitod az appot — márpedig a
        // widget épp azért van, hogy ne kelljen. A betöltött `payload`-ot
        // módosítjuk, nem újat építünk, hogy a pozíciók és a befizetések
        // ne vesszenek el egy párhuzamos írásban.
        if isLive {
            // FRISSEN újraolvasunk közvetlenül írás előtt. A `payload`-ot a
            // hálózati hívások ELŐTT töltöttük be — az azóta eltelt másodpercekben
            // az app is írhatott (kivonat-import, pozíció törlése). A régi
            // másolat visszaírása csendben eldobná azt a munkát.
            var updated = PortfolioFile.load()

            // Ha közben kiürült a portfólió, nincs mit mérni: ne támasszunk fel
            // egy pillanatképet olyan pozíciókból, amiket a felhasználó törölt.
            guard !updated.holdings.isEmpty else { return entry }

            updated.snapshots.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
            // A PLATFORMBONTÁS is bekerül. Enélkül a widget minden frissítéskor
            // egy bontás nélküli sorral írta felül a mai mérést, és a
            // kezdőképernyő közös görbéjéről aznapra eltűntek a vonalak —
            // pont azokon a napokon, amikor nem nyitottad meg az appot.
            updated.snapshots.append(Snapshot(date: today, valueEUR: total, costEUR: cost,
                                              fxRate: fx, isBackfilled: false,
                                              byPlatform: perPlatform))
            updated.snapshots.sort { $0.date < $1.date }
            updated.fxRate = fx
            updated.lastPrices = prices
            updated.lastRefresh = Date()
            PortfolioFile.save(updated)
        }

        // A görbe ugyanabból a sorozatból, mint a kezdőképernyőé: napi
        // ÖSSZVAGYON forintban, plusz a most mért érték a végén.
        entry.sparkline = PortfolioMath.dailyTotalsHUF(payload, days: 29) + [netHUF.doubleValue]
        return entry
    }
}
