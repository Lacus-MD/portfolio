import Foundation

enum Analytics {

    // MARK: - Devizahatás szétválasztása

    struct CurrencySplit {
        /// A teljes forintos eredmény: mai forintérték mínusz a forintban
        /// ténylegesen kifizetett bekerülési érték.
        let totalHUF: Decimal
        /// Ebből amennyit az ETF ÁRA hozott, mai forintra váltva.
        let priceHUF: Decimal
        /// Ebből amennyit a forint mozgása hozott vagy vitt.
        let fxHUF: Decimal
    }

    /// Szétbontja a forintos eredményt ár- és devizahatásra.
    ///
    /// A levezetés:
    ///   teljes  = érték_HUF − beker_HUF        ahol érték_HUF = érték_EUR × mai_fx
    ///   ár      = (érték_EUR − beker_EUR) × mai_fx
    ///   deviza  = teljes − ár = beker_EUR × mai_fx − beker_HUF
    ///           = Σ beker_EUR_i × (mai_fx − fx_i)
    /// vagyis a devizahatás pontosan az, amennyivel a forint elmozdult a
    /// vásárlásaid óta, a befektetett euróösszegre vetítve.
    ///
    /// `nil`, ha nincs meg a forintos bekerülési érték (kézi bevitelnél).
    static func currencySplit(valueEUR: Decimal, costEUR: Decimal,
                              costHUF: Decimal?, fxNow: Decimal) -> CurrencySplit? {
        guard let costHUF, costHUF > 0, fxNow > 0 else { return nil }
        let total = valueEUR * fxNow - costHUF
        let price = (valueEUR - costEUR) * fxNow
        return CurrencySplit(totalHUF: total, priceHUF: price, fxHUF: total - price)
    }

    // MARK: - XIRR

    /// Befizetés-súlyozott éves hozam (XIRR).
    ///
    /// Miért kell: ha havonta más összeget teszel be, a „kezdetektől X%" nem
    /// mond semmit — a tíz napja bent lévő 250 000 Ft nem dolgozott annyit,
    /// mint a két hónapja bent lévő 75 000. Az XIRR minden pénzáramot a saját
    /// dátumán súlyoz.
    ///
    /// Feltevés: minden befizetett forint a követett pozíciókban van. Ha
    /// készpénz áll a számlán, ez a szám pesszimista — a hívónak ezt jeleznie kell.
    static func xirr(deposits: [Deposit], currentValueHUF: Decimal, asOf: Date = Date()) -> Double? {
        let flows: [(Date, Double)] =
            deposits.map { ($0.date, -$0.amountHUF.doubleValue) }
            + [(asOf, currentValueHUF.doubleValue)]

        guard flows.count >= 2,
              flows.contains(where: { $0.1 < 0 }),
              flows.contains(where: { $0.1 > 0 }),
              let first = flows.map(\.0).min() else { return nil }

        func npv(_ rate: Double) -> Double {
            flows.reduce(0) { sum, flow in
                let years = flow.0.timeIntervalSince(first) / (365.25 * 86_400)
                return sum + flow.1 / pow(1 + rate, years)
            }
        }

        // Bisectio, nem Newton: lassabb, de nem szalad el és nem oszt nullával.
        var low = -0.9999, high = 10.0
        guard npv(low) * npv(high) < 0 else { return nil }
        for _ in 0..<200 {
            let mid = (low + high) / 2
            if npv(low) * npv(mid) <= 0 { high = mid } else { low = mid }
        }
        let rate = (low + high) / 2
        return rate.isFinite ? rate * 100 : nil
    }

    // MARK: - Díjak

    struct FeeSummary {
        let total: Decimal
        let byKind: [(FeeItem.Kind, Decimal)]
        /// A díjak aránya az összes befizetéshez képest.
        let shareOfDeposits: Double?
    }

    /// Hány napja van bent a legkorábbi befizetés. Rövid időszakot évesíteni
    /// félrevezető: pár hét ingadozását az évesítés sokszorosára nagyítja.
    static func trackedDays(_ deposits: [Deposit], asOf: Date = Date()) -> Int? {
        guard let first = deposits.map(\.date).min() else { return nil }
        return Calendar.current.dateComponents([.day], from: first, to: asOf).day
    }

    static func fees(_ items: [FeeItem], deposits: [Deposit]) -> FeeSummary? {
        guard !items.isEmpty else { return nil }
        let total = items.reduce(Decimal(0)) { $0 + $1.amountHUF }
        let grouped = Dictionary(grouping: items, by: \.kind)
            .map { ($0.key, $0.value.reduce(Decimal(0)) { $0 + $1.amountHUF }) }
            .sorted { $0.1 > $1.1 }
        let deposited = deposits.reduce(Decimal(0)) { $0 + $1.amountHUF }
        return FeeSummary(
            total: total,
            byKind: grouped,
            shareOfDeposits: deposited > 0 ? (total / deposited).doubleValue * 100 : nil
        )
    }
}

// MARK: - Napi / heti / havi eredmény

extension Analytics {

    /// Egy időszak eredménye.
    ///
    /// **A puszta értékkülönbség nem hozam.** Ha a héten betettél 250 000 Ft-ot,
    /// a vagyonod 250 000-rel nőtt anélkül, hogy egy fillért is kerestél volna.
    /// Ezért az időszak eredménye mindig `záró − nyitó − nettó befizetés`, a
    /// százalék alapja pedig az az összeg, ami tényleg dolgozott.
    struct PeriodChange: Identifiable, Hashable {
        enum Span: Int, CaseIterable {
            case day = 1, week = 7, month = 30

            var title: String {
                switch self {
                case .day: "Ma"
                case .week: "Hét"
                case .month: "Hónap"
                }
            }
        }

        var id: Int { span.rawValue }
        let span: Span
        let from: Date
        let to: Date
        /// Tényleges naptári távolság. Ritkán pont annyi, amennyit a fül ígér —
        /// a mérések nem minden napra esnek, és ezt nem hallgatjuk el.
        let actualDays: Int
        let startHUF: Decimal
        let endHUF: Decimal
        /// Nettó ÚJ pénz az ablakban (a belső átvezetések nélkül).
        let netFlowHUF: Decimal
        /// Hány platform szerepel a számításban, és hány van összesen. Ha
        /// kevesebb, az időszak nem a teljes vagyonról szól — a felület ezt kiírja.
        let coveredPlatforms: Int
        let totalPlatforms: Int

        var gainHUF: Decimal { endHUF - startHUF - netFlowHUF }

        /// Az az összeg, ami az időszakban ténylegesen dolgozott.
        var baseHUF: Decimal { startHUF + max(0, netFlowHUF) }

        var pct: Double {
            guard baseHUF > 0 else { return 0 }
            return (gainHUF / baseHUF).doubleValue * 100
        }

        /// Van-e értelme SZÁZALÉKOT mutatni.
        ///
        /// Ha a számla lényegében az ablakon belül épült fel — a nyitótőke a
        /// záróérték töredéke —, a százalék nem hozamot mér, hanem azt, hogy
        /// mennyire volt kicsi a nevező. Egy 2 800 Ft-ról 400 000-re hízott
        /// számla „+14 000%"-a semmit nem mond. Ilyenkor csak a forintot írjuk ki.
        var isPercentMeaningful: Bool {
            baseHUF > 0 && endHUF > 0 && baseHUF >= endHUF / 5
        }

        var isPartial: Bool { coveredPlatforms < totalPlatforms }
        /// Igaz, ha nem pont annyi napot fog át, amennyit a címke ígér.
        var isApproximate: Bool { actualDays != span.rawValue }
    }

    /// Kiszámolja a napi, heti és havi eredményt a napi mérésekből.
    ///
    /// A mérések platformonként tárolják az értéket, és **nem mindegyik nap
    /// teljes**: a Revolut-kivonatból visszamenőleg csak az adott számla napi
    /// egyenlege van meg, a TBSZ-é nem. Ha a mai teljes vagyont egy ilyen
    /// féloldalas naphoz mérnénk, a „havi hozam" a TBSZ teljes értékét nyereségnek
    /// mutatná. Ezért minden időszak CSAK azokat a platformokat veti össze,
    /// amelyek MINDKÉT végponton szerepelnek — és megmondja, hányat hagyott ki.
    static func periodChanges(snapshots: [Snapshot],
                              todayByPlatform: [String: Decimal],
                              deposits: [Deposit],
                              asOf: Date = Date()) -> [PeriodChange] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: asOf)
        let liveKeys = Set(todayByPlatform.filter { $0.value > 0 }.keys)
        guard !liveKeys.isEmpty else { return [] }

        return PeriodChange.Span.allCases.compactMap { span in
            guard let target = cal.date(byAdding: .day, value: -span.rawValue, to: today),
                  let start = snapshots
                    .filter({ cal.startOfDay(for: $0.date) <= target })
                    .max(by: { $0.date < $1.date })
            else { return nil }

            let startKeys = Set(start.byPlatform.filter { $0.value > 0 }.keys)
            let covered = liveKeys.intersection(startKeys)
            guard !covered.isEmpty else { return nil }

            let startHUF = covered.reduce(Decimal(0)) { $0 + (start.byPlatform[$1] ?? 0) }
            let endHUF = covered.reduce(Decimal(0)) { $0 + (todayByPlatform[$1] ?? 0) }

            let startDay = cal.startOfDay(for: start.date)
            // Szigorúan a nyitómérés UTÁN érkezett pénz — a nyitóérték már
            // tartalmazza az aznapit.
            //
            // A BELSŐ átvezetések is beleszámítanak, és ez szándékos. Az
            // importáló mindkét lábat rögzíti (a küldő oldalon negatív, a
            // fogadón pozitív), így ha mindkét számla benne van az ablakban,
            // kiejtik egymást. Ha viszont csak az egyik — mert a másiknak
            // nincs ilyen régi mérése —, akkor az a pénz ténylegesen KÍVÜLRŐL
            // érkezett a vizsgált körbe, és befizetésként kell kezelni.
            // Kihagyva a megtakarításra átvezetett 398 476 Ft „havi hozamként"
            // jelent meg — mértük.
            let flow = deposits
                .filter { covered.contains($0.account) }
                .filter { cal.startOfDay(for: $0.date) > startDay && $0.date <= asOf }
                .reduce(Decimal(0)) { $0 + $1.amountHUF }

            return PeriodChange(
                span: span,
                from: startDay,
                to: today,
                actualDays: cal.dateComponents([.day], from: startDay, to: today).day ?? 0,
                startHUF: startHUF,
                endHUF: endHUF,
                netFlowHUF: flow,
                coveredPlatforms: covered.count,
                totalPlatforms: liveKeys.count
            )
        }
    }
}
