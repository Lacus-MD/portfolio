import Foundation

/// A Lightyear „Számlakivonat" CSV beolvasása.
///
/// Oszlopok: Date, Reference, Ticker, ISIN, Type, Quantity, CCY, Price/share,
/// Gross Amount, FX Rate, Fee, Net Amt., Tax Amt.
struct StatementImporter {

    struct Result {
        var holdings: [Holding]
        /// Lightyear crypto trades have no ISIN. They are kept separately
        /// from securities, while still belonging to the same Lightyear
        /// account and cash ledger.
        var cryptoPositions: [CryptoPosition]
        var deposits: [Deposit]
        var fees: [FeeItem]
        /// Devizánkénti készpénzegyenleg a kivonat végén (ehhez a számlához).
        var cash: [String: Decimal]
        /// E számla szolgáltatójának átváltási árrése a kivonatból számolva.
        /// Nem beégetett érték: minden új importnál újraszámoljuk.
        var conversionSpread: Decimal?
        /// A kivonatból kinyert TÖRTÉNETI forintérték: minden ügyleti napra
        /// a halmozott darabszám × az aznapi ár × az aznapi árfolyam.
        ///
        /// A Lightyear-kivonatban nincs napi egyenleg (a Revolutéban van),
        /// ezért a görbe nem olvasható ki közvetlenül. A tranzakciókból viszont
        /// igen: minden vételnél ismerjük a darabszámot ÉS az aznapi árat,
        /// tehát az adott napi érték valódi mért adat, nem becslés.
        /// Ritka (annyi pont, ahány ügyleti nap), de igaz.
        var dailyValues: [Date: Decimal] = [:]
        /// ISIN → nap → HALMOZOTT darabszám az adott nap végén.
        ///
        /// Ez teszi a visszatöltést IGAZZÁ. Enélkül a múltat a MAI
        /// darabszámmal kellene visszaszámolni („mennyit érne a mostani
        /// portfólióm, ha végig ez lett volna"), ami minden befizetés előtti
        /// napot felfelé torzít. A kivonatból viszont pontosan tudjuk, hány
        /// darab volt egy adott napon: két ügylet között a darabszám állandó.
        var quantityByDay: [String: [Date: Decimal]] = [:]
        /// Mikor vettél és mikor adtál el — a görbén kis pöttyökkel jelöljük.
        var trades: [TradeMarker] = []
        /// Amit nem tudtunk kezelni — a hívó kiírja, hogy ne csendben vesszen el.
        var warnings: [String]
    }

    enum ImportError: LocalizedError {
        case unreadable, notText(String), noHeader, noTransactions

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "A fájlt nem sikerült beolvasni."
            case .notText(let kind):
                // A megosztólap BÁRMILYEN fájlt átenged, tehát PDF is
                // idekerülhet. Egy „nem sikerült beolvasni" ilyenkor nem
                // segít: megmondjuk, mi a baj és mit kérjen a banktól.
                "Ez \(kind), nem szöveges kivonat. Az app CSV-t (vagy más szövegtáblát) tud beolvasni — a bankok exportjában általában van „CSV” vagy „Excel” formátum is a PDF mellett."
            case .noHeader:
                // Ide jut a beolvasott, de ismeretlen szerkezetű kivonat is
                // (pl. egy bank PDF-je, amihez még nincs elemzőnk). A szöveg
                // MEGVAN, csak a szerkezetét nem ismerjük — ezt mondjuk.
                "A fájlt beolvastam, de a szerkezetét nem ismerem fel. Jelenleg a Lightyear és a Revolut kivonatait tudom értelmezni."
            case .noTransactions:
                "A kivonatban nincs egyetlen ügylet sem."
            }
        }
    }

    private let fx = FXService()

    /// A Lightyear a fájlnévben adja meg a számla azonosítóját
    /// (`AccountStatement-LY-4WY38ZH-…`), a CSV-ben nincs ilyen oszlop.
    /// Ez a mi kulcsunk arra, hogy melyik TBSZ-hez tartozik a kivonat.
    static func accountReference(from fileName: String) -> String? {
        guard let range = fileName.range(of: "LY-[A-Z0-9]+", options: [.regularExpression]) else {
            return nil
        }
        return String(fileName[range])
    }

    func `import`(csv text: String, account: String, tbszYear: Int) async throws -> Result {
        let lines = text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .map(\.withoutUTF8BOM)
        guard let header = lines.first else { throw ImportError.unreadable }
        let cols = Self.parse(line: header)
        guard cols.contains("Type"), cols.contains("Gross Amount") else { throw ImportError.noHeader }
        let index = Dictionary(uniqueKeysWithValues: cols.enumerated().map { ($1, $0) })

        struct Row {
            let date: Date, ticker: String, isin: String, type: String
            let quantity: Decimal, ccy: String, gross: Decimal, fxRate: Decimal, fee: Decimal
            let net: Decimal
        }

        var rows: [Row] = []
        for line in lines.dropFirst() {
            let f = Self.parse(line: line)
            guard f.count >= cols.count,
                  let date = Self.date(f[index["Date"]!]) else { continue }
            rows.append(Row(
                date: date,
                ticker: f[index["Ticker"]!].trimmingCharacters(in: .whitespaces),
                isin: f[index["ISIN"]!].trimmingCharacters(in: .whitespaces),
                type: f[index["Type"]!].trimmingCharacters(in: .whitespaces),
                quantity: Self.number(f[index["Quantity"]!]),
                ccy: f[index["CCY"]!].trimmingCharacters(in: .whitespaces),
                gross: Self.number(f[index["Gross Amount"]!]),
                fxRate: Self.number(f[index["FX Rate"]!]),
                fee: Self.number(f[index["Fee"]!]),
                net: Self.number(f[index["Net Amt."]!])
            ))
        }
        guard !rows.isEmpty else { throw ImportError.noTransactions }

        // Devizatörténet egyszer, a teljes időszakra: a forintos bekerülési
        // értéknek a VÁSÁRLÁSKORI árfolyammal kell számolnia, nem a maival.
        let dates = rows.map(\.date)
        let eurHUF = (try? await fx.rates(from: dates.min()!, to: max(dates.max()!, Date()))) ?? [:]
        let usdHUF = (try? await fx.usdRates(from: dates.min()!, to: max(dates.max()!, Date()))) ?? [:]

        /// Legközelebbi ismert árfolyam: hétvégén és ünnepnapon nincs ECB-jegyzés.
        let rate: ([Date: Decimal], Date) -> Decimal? = { table, date in
            let day = Calendar.current.startOfDay(for: date)
            if let exact = table[day] { return exact }
            return table.filter { $0.key <= day }.max(by: { $0.key < $1.key })?.value
                ?? table.min(by: { $0.key < $1.key })?.value
        }

        // A kivonat tartalmazza a TÉNYLEGES átváltási árfolyamot, amin váltottál —
        // az pontosabb, mint az ECB középárfolyama, mert benne van a szolgáltató
        // árrése is. A Conversion sorokon az EUR oldal FX Rate mezője EUR/HUF-ot
        // ad, ha 100 fölötti; ha 1 körüli, akkor EUR/USD, azt nem használhatjuk.
        var actualEURHUF: [Date: Decimal] = [:]
        for row in rows where row.type == "Conversion" && row.ccy == "EUR" && row.fxRate > 100 {
            actualEURHUF[Calendar.current.startOfDay(for: row.date)] = row.fxRate
        }

        var warnings: [String] = []
        var positions: [String: (qty: Decimal, costEUR: Decimal, costHUF: Decimal,
                                 ticker: String, ccy: String)] = [:]
        /// Lightyear's crypto trades use an empty ISIN and a ticker (ETH,
        /// SOL, UNI, ...). The export has no live crypto valuation, so we
        /// retain net quantity and historical acquisition cost only.
        var crypto: [String: (qty: Decimal, costEUR: Decimal, costHUF: Decimal,
                              ticker: String, ccy: String, asOf: Date?)] = [:]
        var deposits: [Deposit] = []
        var fees: [FeeItem] = []
        var cash: [String: Decimal] = [:]
        var spreadFee: Decimal = 0, spreadBase: Decimal = 0

        for row in rows {
            // Készpénz-vezetés. A kivonat előjel-logikája típusonként más, és
            // ezt MÉRTÜK, nem feltételeztük (a levezetett egyenleg forintra
            // egyezik azzal, amit a Lightyear mutat):
            //   Deposit     — Net == Gross, a díj NEM terheli a számlát
            //   Conversion  — a díj már a Gross-ban van, külön levonni dupla
            //   Buy         — Gross = ár + díj, tehát Gross megy ki
            //   Sell        — Net = ár − díj, tehát Net jön be
            //   Dividend    — Net (forrásadó után)
            switch row.type {
            case "Deposit", "Conversion": cash[row.ccy, default: 0] += row.gross
            case "Buy":                   cash[row.ccy, default: 0] -= row.gross
            case "Sell", "Dividend":      cash[row.ccy, default: 0] += row.net
            default: break
            }

            // Az átváltási árrés a forintból kimenő átváltások díjhányada.
            if row.type == "Conversion", row.ccy == "HUF", row.gross < 0 {
                spreadBase += -row.gross
                spreadFee += row.fee
            }

            // --- Díjak, mindegyik forintra váltva a saját napi árfolyamán ---
            if row.fee > 0 {
                var feeHUF: Decimal?
                switch row.ccy {
                case "HUF": feeHUF = row.fee
                case "EUR": feeHUF = rate(eurHUF, row.date).map { row.fee * $0 }
                case "USD": feeHUF = rate(usdHUF, row.date).map { row.fee * $0 }
                default:    feeHUF = nil
                }
                if let feeHUF {
                    let kind: FeeItem.Kind = row.type == "Deposit" ? .deposit
                                           : row.type == "Conversion" ? .conversion : .trade
                    fees.append(FeeItem(account: account, date: row.date,
                                        amountHUF: feeHUF, kind: kind))
                } else {
                    warnings.append("Ismeretlen devizájú díj (\(row.ccy)) — kihagyva.")
                }
            }

            switch row.type {
            case "Deposit" where row.ccy == "HUF" && row.gross > 0:
                deposits.append(Deposit(account: account, date: row.date, amountHUF: row.gross))

            case "Deposit":
                warnings.append("Nem forintos befizetés (\(row.ccy)) — az XIRR-ből kimarad.")

            case "Buy", "Sell":
                if row.isin.isEmpty, Self.isCryptoTicker(row.ticker) {
                    guard row.quantity > 0 else { continue }
                    let symbol = row.ticker.uppercased()
                    let day = Calendar.current.startOfDay(for: row.date)
                    let historicalRate: Decimal?
                    switch row.ccy.uppercased() {
                    case "EUR": historicalRate = actualEURHUF[day] ?? rate(eurHUF, row.date)
                    case "USD": historicalRate = rate(usdHUF, row.date)
                    default:    historicalRate = nil
                    }

                    guard let historicalRate, historicalRate > 0 else {
                        warnings.append("\(symbol): nincs használható \(row.ccy)\u{2192}HUF árfolyam, a crypto-sor kimaradt.")
                        continue
                    }

                    var p = crypto[symbol] ?? (0, 0, 0, symbol, row.ccy, nil)
                    if row.type == "Buy" {
                        p.qty += row.quantity
                        p.costEUR += row.ccy.uppercased() == "EUR" ? row.gross : 0
                        p.costHUF += row.gross * historicalRate
                        p.asOf = max(p.asOf ?? row.date, row.date)
                    } else {
                        guard p.qty > 0 else {
                            warnings.append("\(symbol): eladás előzmény nélküli, ezért nem vontuk le a mennyiségből.")
                            continue
                        }
                        let sold = min(row.quantity, p.qty)
                        let share = sold / p.qty
                        p.costEUR -= p.costEUR * share
                        p.costHUF -= p.costHUF * share
                        p.qty -= sold
                        p.asOf = max(p.asOf ?? row.date, row.date)
                        if sold < row.quantity {
                            warnings.append("\(symbol): az eladás nagyobb volt a követett mennyiségnél; csak a meglévő darabszámot vontuk le.")
                        }
                    }
                    crypto[symbol] = p
                    continue
                }
                guard !row.isin.isEmpty, row.quantity > 0 else { continue }
                var p = positions[row.isin] ?? (0, 0, 0, row.ticker, row.ccy)
                // A forintos bekerülési érték csak euróban jegyzett papírnál értelmes;
                // a dollárosokat nem forintosítjuk vissza kétszeres átváltással.
                let day = Calendar.current.startOfDay(for: row.date)
                let eurRate = actualEURHUF[day] ?? rate(eurHUF, row.date)
                let huf = row.ccy == "EUR" ? (eurRate.map { row.gross * $0 } ?? 0)
                                           : (rate(usdHUF, row.date).map { row.gross * $0 } ?? 0)
                if row.type == "Buy" {
                    p.qty += row.quantity; p.costEUR += row.gross; p.costHUF += huf
                } else {
                    // Eladásnál arányosan csökkentjük a bekerülési értéket (átlagáras módszer).
                    let share = p.qty > 0 ? row.quantity / p.qty : 0
                    p.costEUR -= p.costEUR * share
                    p.costHUF -= p.costHUF * share
                    p.qty -= row.quantity
                }
                positions[row.isin] = p

            default:
                break
            }
        }

        // A TBSZ gyűjtőéve a legkorábbi befizetés éve — ezt nem kell kitalálni,
        // a kivonatban benne van. A paraméter csak tartalék, ha nincs befizetés.
        let year = deposits.map { Calendar.current.component(.year, from: $0.date) }.min() ?? tbszYear

        // Történeti értékpontok: végigmegyünk az ügyleteken időrendben, és
        // minden nap végén kiszámoljuk, mennyit ért a MEGLÉVŐ állomány az
        // aznapi áron.
        var dailyValues: [Date: Decimal] = [:]
        var tradeMarkers: [TradeMarker] = []
        var running: [String: (qty: Decimal, price: Decimal)] = [:]
        var quantityByDay: [String: [Date: Decimal]] = [:]
        for row in rows.sorted(by: { $0.date < $1.date })
        where (row.type == "Buy" || row.type == "Sell") && !row.isin.isEmpty && row.ccy == "EUR" {
            var entry = running[row.isin] ?? (0, 0)
            entry.qty += row.type == "Buy" ? row.quantity : -row.quantity
            // Az ügylet ára az adott napi piaci ár — ezt méri a kivonat.
            if row.quantity > 0 { entry.price = row.gross / row.quantity }
            running[row.isin] = entry

            let day = Calendar.current.startOfDay(for: row.date)
            tradeMarkers.append(TradeMarker(
                platform: account,
                day: ConstituentWatcher.dayKey(day),
                kind: row.type == "Buy" ? .buy : .sell
            ))
            quantityByDay[row.isin, default: [:]][day] = entry.qty
            let valueEUR = running.values.reduce(Decimal(0)) { $0 + $1.qty * $1.price }
            let rate = actualEURHUF[day] ?? rate(eurHUF, row.date) ?? 0
            if rate > 0 { dailyValues[day] = valueEUR * rate }
        }

        var holdings: [Holding] = []
        for (isin, p) in positions {
            guard p.qty > Decimal(string: "0.000000001")! else { continue }
            guard p.ccy == "EUR" else {
                warnings.append("\(p.ticker): \(p.ccy) devizában jegyzett, az app euróval számol — kihagyva.")
                continue
            }
            let name = Holding.catalog.first { $0.isin == isin }?.name ?? p.ticker
            holdings.append(Holding(
                account: account,
                isin: isin, ticker: p.ticker, name: name,
                quantity: p.qty, averageCost: p.costEUR / p.qty,
                tbszYear: year, costHUF: p.costHUF
            ))
        }
        holdings.sort { $0.ticker < $1.ticker }

        let cryptoPositions = crypto.compactMap { symbol, p -> CryptoPosition? in
            guard p.qty > Decimal(string: "0.000000001")!, p.costHUF > 0 else { return nil }
            let name = Self.cryptoName(for: symbol)
            // The transaction export contains acquisition data, not a current
            // market snapshot. Keeping the cost as the displayed value avoids
            // inventing a quote; the warning below makes this limitation clear.
            return CryptoPosition(
                id: "\(account):crypto:\(symbol)",
                platform: account,
                symbol: symbol,
                name: name,
                quantity: p.qty,
                currentValueHUF: p.costHUF,
                investedValueHUF: p.costHUF,
                unitPriceHUF: p.qty > 0 ? p.costHUF / p.qty : nil,
                asOf: p.asOf,
                source: "Lightyear crypto · bekerülési érték"
            )
        }.sorted { $0.symbol < $1.symbol }

        if !cryptoPositions.isEmpty {
            warnings.append("Lightyear crypto: \(cryptoPositions.count) pozíció került be bekerülési értéken; ez az export nem tartalmaz aktuális piaci értéket.")
        }

        if eurHUF.isEmpty {
            warnings.append("Nem sikerült devizatörténetet letölteni — a forintos bekerülési érték hiányzik.")
        }
        if dailyValues.count >= 2 {
            warnings.append("\(dailyValues.count) ügyleti napból visszaszámolt görbe — a Lightyear-kivonat nem tartalmaz napi egyenleget, ezért csak ennyi pont van.")
        }

        return Result(holdings: holdings, cryptoPositions: cryptoPositions,
                      deposits: deposits, fees: fees,
                      cash: cash.filter { abs($0.value) > Decimal(string: "0.005")! },
                      conversionSpread: spreadBase > 0 ? spreadFee / spreadBase : nil,
                      dailyValues: dailyValues,
                      quantityByDay: quantityByDay,
                      trades: tradeMarkers,
                      warnings: warnings)
    }

    // MARK: - Elemzés

    /// Idézőjeleket kezelő CSV-sorbontó. A Lightyear minden mezőt idézőjelez,
    /// de a vesszőt tartalmazó alapnevek miatt nem elég a sima `split`.
    static func parse(line: String, delimiter: Character = ",") -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(line.withoutUTF8BOM)
        var index = 0
        while index < characters.count {
            let char = characters[index]
            if char == "\"" {
                // CSV escapes a quote inside a quoted field as two quotes.
                if inQuotes, index + 1 < characters.count,
                   characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                inQuotes.toggle()
            } else if char == delimiter, !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        fields.append(current)
        return fields
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Budapest")
        f.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return f
    }()

    static func date(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if let d = formatter.date(from: t) { return d }
        // Néhány kivonatban nincs időpont, csak dátum.
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.timeZone = TimeZone(identifier: "Europe/Budapest")
        short.dateFormat = "dd/MM/yyyy"
        return short.date(from: t)
    }

    static func number(_ text: String) -> Decimal {
        // Lightyear exports quantities with a fixed-point dot and can keep
        // up to nine fractional digits (for example `1.000000000`). The
        // Hungarian/locale parser intentionally treats a dot followed by
        // three digits as a thousands separator, which would turn that value
        // into one billion shares. Lightyear is a separate, English-column
        // format, so parse its numeric fields with a dot-first rule.
        let t = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{2009}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty else { return 0 }

        let comma = t.lastIndex(of: ",")
        let dot = t.lastIndex(of: ".")
        let decimalSeparator: Character?
        switch (comma, dot) {
        case let (comma?, dot?):
            // Whichever separator appears last is the decimal separator.
            // This also tolerates a locale-formatted file such as 1.234,56.
            decimalSeparator = comma > dot ? "," : "."
        case (nil, _?):
            // Unlike the Hungarian parser, ANY dot is decimal here — this is
            // what preserves Lightyear's fractional-share precision.
            decimalSeparator = "."
        case let (comma?, nil):
            // A comma-only localized amount is decimal when its fractional
            // part is not a three-digit grouping. Canonical Lightyear files
            // use a dot, so the ambiguous 1,000 form remains one thousand.
            let trailing = t.distance(from: t.index(after: comma), to: t.endIndex)
            decimalSeparator = trailing == 3 ? nil : ","
        case (nil, nil):
            decimalSeparator = nil
        }

        var normalized = t
        if let decimalSeparator {
            let grouping = decimalSeparator == "." ? "," : "."
            normalized = normalized.replacingOccurrences(of: String(grouping), with: "")
            normalized = normalized.replacingOccurrences(of: String(decimalSeparator), with: ".")
        } else {
            normalized = normalized
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Tickers currently used by Lightyear's crypto trading export. An empty
    /// ISIN alone is not enough to classify a row: conversions and cash rows
    /// also have no ISIN, so keep the allow-list explicit.
    private static func isCryptoTicker(_ raw: String) -> Bool {
        let symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return [
            "BTC", "ETH", "SOL", "UNI", "XRP", "ADA", "DOT", "AVAX", "LINK",
            "LTC", "BCH", "DOGE", "SHIB", "MATIC", "POL", "ATOM", "AAVE",
            "ALGO", "XLM", "NEAR", "FIL", "TRX", "SAND", "MANA", "USDT",
            "USDC", "DAI", "OP", "ARB"
        ].contains(symbol)
    }

    private static func cryptoName(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "Bitcoin"
        case "ETH": return "Ethereum"
        case "SOL": return "Solana"
        case "UNI": return "Uniswap"
        case "XRP": return "XRP"
        case "ADA": return "Cardano"
        case "DOT": return "Polkadot"
        case "AVAX": return "Avalanche"
        case "LINK": return "Chainlink"
        case "LTC": return "Litecoin"
        case "BCH": return "Bitcoin Cash"
        case "DOGE": return "Dogecoin"
        case "SHIB": return "Shiba Inu"
        case "MATIC", "POL": return "Polygon"
        case "ATOM": return "Cosmos"
        case "AAVE": return "Aave"
        case "ALGO": return "Algorand"
        case "XLM": return "Stellar"
        case "NEAR": return "NEAR Protocol"
        case "FIL": return "Filecoin"
        case "TRX": return "TRON"
        case "SAND": return "The Sandbox"
        case "MANA": return "Decentraland"
        case "USDT": return "Tether"
        case "USDC": return "USD Coin"
        case "DAI": return "Dai"
        case "OP": return "Optimism"
        case "ARB": return "Arbitrum"
        default: return symbol
        }
    }
}
