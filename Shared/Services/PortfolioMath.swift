import Foundation

/// A portfólió számításai EGY helyen, közvetlenül a tárolt állományból.
///
/// **Miért kell:** a widget korábban a saját, párhuzamos matekját futtatta —
/// csak az értékpapírokból, euróban, a bekerülési árhoz mérve. Az app közben
/// platformonként, forintban, a BEFIZETÉSEKHEZ mérve számolt. Ugyanaz a
/// portfólió két felületen két különböző igazságot mutatott: a widgeten egy
/// tétel 100%-on, más görbével. Ez nem elírás volt, hanem szerkezeti hiba —
/// két hely, ahol ugyanazt kell karbantartani.
///
/// Ezért a számítás payload-alapú és `Shared`-ben él: az app tára és a widget
/// is EZT hívja, tehát nem tudnak elcsúszni.
enum PortfolioMath {

    /// A számításhoz kellő élő árak. A tár és a widget külön szerzi be őket.
    struct Prices {
        var quotes: [String: Decimal] = [:]
        var fxRate: Decimal = 0
        var usdRate: Decimal = 0
    }

    // MARK: - Váltás

    static func convertToHUF(_ amount: Decimal, currency: String, prices: Prices) -> Decimal {
        switch currency {
        case "HUF": return amount
        case "EUR": return amount * prices.fxRate
        case "USD": return prices.usdRate > 0 ? amount * prices.usdRate : 0
        default:    return 0
        }
    }

    /// Egy pozíció forintos értéke az adott számla átváltási árrésével
    /// csökkentve — a bróker is így értékel.
    static func netValueHUF(of holding: Holding, in payload: PortfolioFile.Payload,
                            prices: Prices) -> Decimal? {
        guard let price = prices.quotes[holding.isin] else { return nil }
        let spread = payload.conversionSpread[holding.account] ?? 0
        return holding.quantity * price * prices.fxRate * (1 - spread)
    }

    // MARK: - Platformok

    /// A követett platformok. Ha nincs kézzel megadott lista, a pozíciók és a
    /// készpénz-eszközök számláiból származtatjuk.
    static func resolvedPlatforms(_ payload: PortfolioFile.Payload) -> [Platform] {
        let known = Set(payload.platforms.map(\.id))
        let ids = Set(payload.holdings.map(\.account))
            .union(payload.cashAssets.map(\.platform))
            .subtracting(known)
            .sorted()
        let usedAccents = Set(payload.platforms.map(\.accent))
        let accents = Platform.Accent.allCases.filter { !usedAccents.contains($0) }
            + Platform.Accent.allCases
        let derived = ids.enumerated().map { index, id -> Platform in
            let hasSecurities = payload.holdings.contains { $0.account == id }
            return Platform(
                id: id,
                name: displayName(forAccount: id, in: payload),
                kind: hasSecurities ? .brokerage : .savings,
                accent: accents[index % accents.count],
                tbszYear: payload.holdings.first { $0.account == id }?.tbszYear
            )
        }
        return payload.platforms + derived
    }

    /// Emberi név egy nyers számlaazonosítóhoz. A Lightyear-hivatkozásból
    /// (`LY-4WY38ZH`) nem derül ki semmi, ezért a rajta lévő papírt írjuk ki.
    static func displayName(forAccount id: String, in payload: PortfolioFile.Payload) -> String {
        let tickers = payload.holdings.filter { $0.account == id }.map(\.ticker)
        if let year = payload.holdings.first(where: { $0.account == id })?.tbszYear,
           let ticker = tickers.first {
            return "TBSZ \(String(year)) · \(ticker)"
        }
        if let ticker = tickers.first { return ticker }
        if let asset = payload.cashAssets.first(where: { $0.platform == id }) { return asset.name }
        return id
    }

    static func valueHUF(ofPlatform id: String, in payload: PortfolioFile.Payload,
                         prices: Prices) -> Decimal {
        let securities = payload.holdings
            .filter { $0.account == id }
            .reduce(Decimal(0)) { $0 + (netValueHUF(of: $1, in: payload, prices: prices) ?? 0) }

        let brokerCash = (payload.cash[id] ?? [:]).reduce(Decimal(0)) { sum, entry in
            sum + convertToHUF(entry.value, currency: entry.key, prices: prices)
        }

        // A BECSÜLT egyenleg: a kivonat záró értéke a mért nettó kulccsal a mai
        // napig görgetve.
        let savings = payload.cashAssets
            .filter { $0.platform == id }
            .reduce(Decimal(0)) {
                $0 + convertToHUF($1.estimatedBalance(), currency: $1.currency, prices: prices)
            }

        return securities + brokerCash + savings
    }

    static func depositsHUF(ofPlatform id: String, in payload: PortfolioFile.Payload) -> Decimal {
        payload.deposits.filter { $0.account == id }.reduce(0) { $0 + $1.amountHUF }
    }

    // MARK: - Összesítés

    static func totalHUF(_ payload: PortfolioFile.Payload, prices: Prices) -> Decimal {
        resolvedPlatforms(payload).reduce(Decimal(0)) {
            $0 + valueHUF(ofPlatform: $1.id, in: payload, prices: prices)
        }
    }

    /// Az összesített befizetés csak a KÍVÜLRŐL érkezett pénzt számolja.
    /// A követett platformok közti átvezetés nem új pénz — beszámítva ugyanaz
    /// a forint kétszer szerepelne. Ha viszont csak az egyik oldal kivonata
    /// van meg, a maradék valódi külső pénz.
    static func depositsHUF(_ payload: PortfolioFile.Payload) -> Decimal {
        // A FOLYÓSZÁMLÁK tételei kimaradnak. Az értékük benne van a nettó
        // vagyonban, de a hozamban nincs keresnivalójuk: oda a fizetés
        // érkezik és onnan költesz, nem befektetsz. Az egyensúly kedvéért
        // ugyanez a szűrés fut az `assetsHUF`-on is — különben a folyószámla
        // értéke hozamnak látszana.
        let transactional = Set(resolvedPlatforms(payload)
            .filter(\.isTransactional).map(\.id))
        let relevant = payload.deposits.filter { !transactional.contains($0.account) }
        let external = relevant.filter { !$0.isInternal }
            .reduce(Decimal(0)) { $0 + $1.amountHUF }
        let internalNet = relevant.filter(\.isInternal)
            .reduce(Decimal(0)) { $0 + $1.amountHUF }
        return external + max(0, internalNet)
    }

    /// Napi ÖSSZVAGYON forintban, a mérésekből — ugyanaz a sorozat, amiből a
    /// kezdőképernyő közös görbéje épül. A widget szikragörbéje korábban az
    /// értékpapírok EURÓS értékét rajzolta, ezért nézett ki másképp.
    static func dailyTotalsHUF(_ payload: PortfolioFile.Payload, days: Int = 30) -> [Double] {
        payload.snapshots
            .sorted { $0.date < $1.date }
            .suffix(days)
            .map { snapshot in
                let byPlatform = snapshot.byPlatform.values.reduce(Decimal(0), +)
                // Régi mérésekben még nincs platformbontás: ott a nyers
                // értékpapír-érték az egyetlen, amit tudunk.
                return (byPlatform > 0 ? byPlatform : snapshot.valueEUR * snapshot.fxRate)
                    .doubleValue
            }
    }
}
