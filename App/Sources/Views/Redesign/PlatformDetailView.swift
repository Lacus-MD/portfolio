import SwiftUI

/// 3c — Egy platform részletei: görbe, eszközök, díjak, TBSZ-visszaszámláló.
struct PlatformDetailView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let summary: PlatformSummary

    @State private var range: ChartRange = .max
    @State private var movers: [ConstituentMove] = []
    @State private var inspecting: ConstituentMove?

    /// A platform saját akcentusa. A kezdőképernyőn minden kártya más színű,
    /// ezért a részletnézetnek is azt kell vinnie — különben a belépéssel
    /// elveszik, hogy melyik platformban vagy.
    private var platformTint: Color { summary.platform.accent.color }

    /// Szöveg a platform színén — a mentán és a lilán sötét kell.
    private var onTint: Color { summary.platform.accent.ink }

    private var holdings: [Holding] {
        store.holdings.filter { $0.account == summary.platform.id }
    }
    private var savings: [CashAsset] {
        store.cashAssets.filter { $0.platform == summary.platform.id }
    }

    var body: some View {
        // EGYETLEN görgethető oszlop. Korábban az alsó lap fix panel volt a
        // ZStack alján — a handoffban pár sor fért bele, de azóta idekerült az
        // eszközlista, az összetétel-gyűrű, a TBSZ-kalkulátor és a díjak.
        // Fix panelként ez nem görgethető és tömör: a tartalom egyszerűen
        // kifutott a képernyőből.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    statPair
                    shortHistoryNote
                    chart
                    RangeChips(selection: $range, tint: platformTint, onTint: onTint,
                               ink: DS.Color.onShell())
                }
                .padding(.horizontal, 22)
                .padding(.top, DS.topPadding)

                sheet
            }
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .background(DS.Color.plumDeep)
        // A 58 pt-es felső padding NYELI EL a státuszsáv helyét (handoff).
        .ignoresSafeArea(edges: .top)
        .foregroundStyle(DS.Color.onShell())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $inspecting) { ConstituentDetailView(move: $0) }
    }

    // MARK: - Fejléc

    private var header: some View {
        HStack(spacing: 16) {
            GlassCloseButton { dismiss() }

            Text(summary.platform.name).font(DS.screenTitle).lineLimit(1)
            Spacer(minLength: 8)

            if let badge = tbszBadge {
                // Korábban „D-131" állt itt — rejtjel, nem információ.
                VStack(alignment: .trailing, spacing: 1) {
                    Text(badge.value).font(DS.font(13, .semibold))
                    Text(badge.caption)
                        .font(DS.font(10, .regular))
                        .foregroundStyle(DS.Color.onPlum(0.6))
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(DS.Color.onShell(0.12), in: .rect(cornerRadius: DS.R.valueTag))
            }
        }
    }

    /// Hány nap a gyűjtőév zárásáig — eddig lehet befizetni erre a TBSZ-re.
    /// Naptári tény, nem adótanács.
    private var tbszBadge: (value: String, caption: String)? {
        guard let year = summary.platform.tbszYear,
              let end = PortfolioStore.collectionYearEnd(year),
              let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day,
              days >= 0 else { return nil }
        return ("\(days) nap", "befizetésig")
    }

    private var statPair: some View {
        HStack(alignment: .top, spacing: 38) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Befizetés").font(DS.font(11.5, .regular))
                    .foregroundStyle(DS.Color.onPlum(0.55))
                Odometer(text: Fmt.huf(summary.depositsHUF), font: DS.stat,
                         cellHeight: 24, delay: 0.25)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(annualised != nil ? "Éves hozam (XIRR)" : "Hozam kezdetektől")
                    .font(DS.font(11.5, .regular))
                    .foregroundStyle(DS.Color.onPlum(0.55))
                if summary.isMissingValue {
                    Text("hiányzó adat").font(DS.stat)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Fmt.percent(annualised ?? summary.gainPct)).font(DS.stat)
                        // A forintos összeg: enélkül a százalékból nem derül ki,
                        // mennyi pénzről van szó.
                        Text((summary.gainHUF >= 0 ? "+" : "") + Fmt.huf(summary.gainHUF))
                            .font(DS.font(12, .medium))
                            .foregroundStyle(DS.Color.sign(summary.gainPct))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Befizetés-súlyozott éves hozam. Rövid előzménynél nem mutatjuk
    /// évesítve — pár hét ingadozását az évesítés sokszorosára nagyítja,
    /// és ezt a figyelmeztetést a handoff is megtartandónak jelöli.
    private var annualised: Double? {
        guard let days = store.trackedDays(ofPlatform: summary.platform.id),
              days >= 180 else { return nil }
        return store.xirr(ofPlatform: summary.platform.id)
    }

    /// Csak akkor szólunk, ha tényleg rövid az előzmény. Fél évnél a
    /// „kezdetektől" mért százalék önmagában értelmes szám — nem kell
    /// mentegetni. Korábban 173 napnál is azt írta ki, hogy „csak", és arról
    /// beszélt, ami NINCS (évesítés), ahelyett hogy megmondta volna, mi VAN.
    @ViewBuilder private var shortHistoryNote: some View {
        if let days = store.trackedDays(ofPlatform: summary.platform.id), days < 90 {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle").font(.system(size: 10))
                Text("\(days) nap előzmény. Ilyen rövid szakaszon a százalék még sokat ugrálhat.")
                    .font(DS.meta)
            }
            .foregroundStyle(DS.Color.onPlum(0.5))
        }
    }

    // MARK: - Görbe

    /// EZ A PLATFORM saját napi értékei — nem a teljes portfólióé.
    /// (Korábban a portfólió-görbét rajzolta minden platform alatt.)
    private var series: [(date: Date, value: Double)] {
        let all = store.snapshots
            .compactMap { snapshot -> (Date, Double)? in
                guard let value = snapshot.byPlatform[summary.platform.id] else { return nil }
                return (snapshot.date, value.doubleValue)
            }
            .sorted { $0.0 < $1.0 }
        guard let cutoff = range.cutoff else { return all }
        return all.filter { $0.0 >= cutoff }
    }

    @ViewBuilder private var chart: some View {
        if series.count >= 2 {
            let values = series.map(\.value)
            let chart = AreaChart(points: values, tint: platformTint,
                                  valueTag: Fmt.huf(summary.valueHUF),
                                  markers: tradeMarkers,
                                  dates: series.map(\.date))
            VStack(alignment: .leading, spacing: 6) {
                chart
                    // Kitölti a rendelkezésre álló magasságot: rövid tartalomnál
                    // korábban üres sáv maradt a grafikon és a chipek között.
                    .frame(minHeight: 150, maxHeight: .infinity)
                // Néma torzítás nem lehet: ami nem nyers adat, azt kiírjuk.
                if chart.scale == .logarithmic || chart.isSmoothed {
                    Text(chartNote(chart))
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.onPlum(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            chartEmpty
        }
    }

    private var chartEmpty: some View {
        VStack(spacing: 11) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24))
                .foregroundStyle(platformTint)
                .frame(width: 52, height: 52)
                .background(platformTint.opacity(0.22), in: .circle)
            Text("A görbe a mai naptól épül").font(DS.font(15, .medium))
            Text("Az app naponta elment egy mérést. A widget akkor is dolgozik, ha nem nyitod meg.")
                .font(DS.font(11.5, .regular))
                .foregroundStyle(DS.Color.onPlum(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 10)
    }

    // MARK: - Alsó lap

    /// „Mi lenne, ha…" — a kamatos-kamat számoló.
    ///
    /// Korábban a kezdőképernyőn állt, de ott nem tartozott sehová: a
    /// kamatos kamat egy BEFEKTETÉSI számlára vonatkozik, nem az összesített
    /// vagyonra, amiben hitelkártya-tartozás is van. Ezért itt a helye, a
    /// befektetési platform részletei alatt.
    @ViewBuilder private var scenarioLink: some View {
        if summary.platform.kind == .brokerage {
            Divider().overlay(DS.Color.onPlum(0.1)).padding(.vertical, 10)
            NavigationLink {
                ScenarioView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "function")
                        .font(.system(size: 15))
                        .foregroundStyle(onTint)
                        .frame(width: 38, height: 38)
                        .background(platformTint, in: .rect(cornerRadius: DS.R.rowIcon))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mi lenne, ha…").font(DS.rowTitle)
                        Text("Kamatos kamat a te feltevéseiddel")
                            .font(DS.meta).foregroundStyle(DS.Color.onPlum(0.45))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12)).foregroundStyle(DS.Color.onPlum(0.35))
                }
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(DS.Color.onShell())
        }
    }

    private func chartNote(_ chart: AreaChart) -> String {
        var parts: [String] = []
        if chart.isSmoothed { parts.append("\(chart.window) napos simítás") }
        if chart.scale == .logarithmic { parts.append("logaritmikus skála") }
        return parts.joined(separator: " · ")
            + " — az alakot mutatja, nem a napi pontos értéket. A mai összeg fent olvasható."
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Eszközök").font(DS.section)
                Spacer()
                Text(assetMeta).font(DS.font(11, .regular))
                    .foregroundStyle(DS.Color.onPlum(0.45))
            }
            .padding(.bottom, 10)

            ForEach(holdings) { holding in
                assetRow(
                    monogram: String(holding.ticker.prefix(2)),
                    name: holding.name,
                    meta: "\(Fmt.decimal(holding.quantity)) db · átlag \(Fmt.eur(holding.averageCost))",
                    value: store.netValueHUF(for: holding) ?? 0,
                    delta: deltaPct(for: holding)
                )
            }
            ForEach(savings) { asset in
                assetRow(
                    monogram: String(asset.name.prefix(2)).uppercased(),
                    name: asset.name,
                    meta: savingsMeta(asset),
                    value: store.convertToHUF(asset.estimatedBalance(), currency: asset.currency),
                    delta: nil
                )
            }

            composition
            tbszCard
            scenarioLink

            if let fees = feeSummary {
                Divider().overlay(DS.Color.onPlum(0.1)).padding(.vertical, 10)
                HStack {
                    Text("Levont díjak").font(DS.label)
                        .foregroundStyle(DS.Color.onPlum(0.6))
                    Spacer()
                    Text(Fmt.huf(fees.total) + (fees.shareOfDeposits.map { String(format: " · %.2f%%", $0) } ?? ""))
                        .font(DS.font(12.5, .medium))
                }
                FeeSplitBar(items: fees.byKind)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        // A tab bar magassága, hogy a lap alja ne kerüljön alá.
        .padding(.bottom, DS.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.plum)
        .clipShape(.rect(topLeadingRadius: DS.R.sheet, topTrailingRadius: DS.R.sheet))
    }

    private var assetMeta: String {
        let count = holdings.count + savings.count
        return count == 1 ? "1 eszköz" : "\(count) eszköz"
    }

    /// A kamat és az, hogy MELYIK NAPRA szól az egyenleg. Az app nem
    /// kamatoztat magától — a szám a kivonat záró értéke.
    private func savingsMeta(_ asset: CashAsset) -> String {
        var parts: [String] = []
        if let rate = asset.netDailyRate {
            parts.append(String(format: "%.2f%% nettó", rate.doubleValue * 365 * 100))
        } else if let rate = asset.annualRatePct {
            parts.append(String(format: "%.2f%% EBKM", rate))
        }
        let days = asset.daysSinceStatement()
        if days > 0, asset.netDailyRate != nil {
            parts.append("+\(Fmt.huf(asset.estimatedInterest())) becsülve \(days) napra")
        } else if let asOf = asset.asOf {
            parts.append("\(Fmt.day(asOf))-i kivonat")
        }
        return parts.joined(separator: " · ")
    }

    private func deltaPct(for holding: Holding) -> Double? {
        guard holding.costBasis > 0, let value = store.value(for: holding) else { return nil }
        return ((value - holding.costBasis) / holding.costBasis).doubleValue * 100
    }

    private func assetRow(monogram: String, name: String, meta: String,
                          value: Decimal, delta: Double?) -> some View {
        HStack(spacing: 13) {
            Text(monogram.uppercased())
                .font(DS.monogram)
                .foregroundStyle(onTint)
                .frame(width: 40, height: 40)
                .background(platformTint, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(DS.rowTitle).lineLimit(1)
                Text(meta).font(DS.meta).foregroundStyle(DS.Color.onPlum(0.45))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.huf(value)).font(DS.font(13.5, .medium))
                if let delta {
                    Text(Fmt.percent(delta)).font(DS.meta).foregroundStyle(platformTint)
                }
            }
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.onPlum(0.1)).frame(height: 1)
        }
    }

    /// A görbe melyik pontjára esik vétel vagy eladás.
    private var tradeMarkers: [Int: TradeMarker.Kind] {
        let days = series.map { ConstituentWatcher.dayKey($0.date) }
        var result: [Int: TradeMarker.Kind] = [:]
        for trade in store.trades where trade.platform == summary.platform.id {
            if let index = days.firstIndex(of: trade.day) {
                // Eladás felülírja a vételt ugyanazon a napon: az a ritkább
                // és a figyelemre méltóbb esemény.
                if result[index] != .sell { result[index] = trade.kind }
            }
        }
        return result
    }

    /// Az alap összetétele, ha ismerjük. Csak egy értékpapírt tartó
    /// platformnál mutatjuk — kevert számlánál félrevezető lenne.
    @ViewBuilder private var composition: some View {
        if holdings.count == 1, let first = holdings.first,
           let known = FundComposition.known[first.isin] {
            Divider().overlay(DS.Color.onPlum(0.1)).padding(.vertical, 10)
            // A .task a MINDIG LÉTEZŐ konténerre kerül. Korábban a
            // `moversSection`-höz volt kötve, ami viszont csak akkor
            // renderelődik, ha már van adat — így sosem futott le.
            VStack(alignment: .leading, spacing: 12) {
                CompositionRing(composition: known, tint: platformTint)
                moversSection
            }
            .task {
                // Csak akkor hálózunk hírért, ha valami tényleg nagyot mozdult.
                movers = await ConstituentWatcher().snapshot(of: known)
            }
        }
    }

    /// Csak a kiugró mozgások. Egy 3 757 papírból álló indexnél a napi
    /// komponens-hírfolyam zaj lenne; az viszont érdekes, ha valami nagyot
    /// esett vagy emelkedett. A súly mindig ott van mellette, hogy látszódjon,
    /// mennyit mozdít ez ténylegesen az alapon.
    @ViewBuilder private var moversSection: some View {
        if !movers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Az alap legnagyobb tételei · koppints a részletekért")
                    .font(DS.font(12, .medium))
                    .foregroundStyle(DS.Color.onPlum(0.6))

                ForEach(movers) { mover in
                    Button { inspecting = mover } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(mover.name).font(DS.rowTitle)
                            Text(Fmt.eur(mover.price))
                                .font(DS.meta.monospacedDigit())
                                .foregroundStyle(DS.Color.onPlum(0.5))
                            Text(Fmt.percent(mover.changePct))
                                .font(DS.font(12.5, .semibold).monospacedDigit())
                                .foregroundStyle(DS.Color.sign(mover.changePct))
                            Spacer(minLength: 4)
                            Text(String(format: "%@ az alapon",
                                        Fmt.percent(mover.contributionPct, digits: 2)))
                                .font(DS.meta)
                                .foregroundStyle(DS.Color.onPlum(0.45))
                        }
                        if let headline = mover.headline {
                            Link(destination: URL(string: mover.link ?? "") ?? URL(string: "https://news.google.com")!) {
                                Text(headline)
                                    .font(DS.meta)
                                    .foregroundStyle(DS.Color.onPlum(0.6))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.onShell())
                }
            }
            .padding(.top, 4)
        }
    }

    /// Mennyi jönne ki ténylegesen feltöréskor — ma, 3 és 5 év múlva.
    ///
    /// Mindhárom szám a MAI egyenleggel számol. Nem jóslat arról, mennyi lesz
    /// a pénzed három év múlva — azt senki nem tudja. Azt mutatja, hogy a
    /// mostani nyereségedből mennyit vinne el az adó az adott sávban.
    @ViewBuilder private var tbszCard: some View {
        if let year = summary.platform.tbszYear {
            let rules = store.rules(forCollectionYear: year)
            let scenarios = TBSZCalculator.scenarios(
                value: summary.valueHUF, deposits: summary.depositsHUF,
                collectionYear: year, rules: rules
            )
            Divider().overlay(DS.Color.onPlum(0.1)).padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Ha most feltörnéd").font(DS.section)
                    Spacer()
                    Text("adóalap \(Fmt.huf(scenarios[0].taxableGain))")
                        .font(DS.font(11, .regular))
                        .foregroundStyle(DS.Color.onPlum(0.45))
                }

                ForEach(scenarios) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label).font(DS.rowTitle)
                            Text(scenarioMeta(s))
                                .font(DS.meta)
                                .foregroundStyle(DS.Color.onPlum(0.45))
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.huf(s.netWithdrawal))
                                .font(DS.font(13.5, .medium))
                                .foregroundStyle(s.isAvailableNow ? DS.Color.onShell() : DS.Color.onShell(0.75))
                            if s.tax > 0 {
                                Text("−\(Fmt.huf(s.tax)) adó")
                                    .font(DS.meta)
                                    .foregroundStyle(DS.Color.negativeCream)
                            } else {
                                Text("adómentes").font(DS.meta).foregroundStyle(DS.Color.positiveGreen)
                            }
                        }
                    }
                    .padding(.vertical, 11)
                }

                Text("A kulcsok szerkeszthető alapértékek, nem az app állításai a jogról — jogszabálytól függenek és változnak. A beállításokban átírhatod; ellenőrizd a NAV-nál vagy a számlavezetődnél.")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.onPlum(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scenarioMeta(_ s: TBSZScenario) -> String {
        var parts = [String(format: "%.0f%% adó a nyereségre", s.ratePct)]
        if let from = s.from {
            parts.append(Fmt.day(from))
            if s.daysAway > 0 { parts.append("még \(s.daysAway) nap") }
        }
        return parts.joined(separator: " · ")
    }

    private var feeSummary: Analytics.FeeSummary? {
        let own = store.fees.filter { $0.account == summary.platform.id }
        let ownDeposits = store.deposits.filter { $0.account == summary.platform.id }
        return Analytics.fees(own, deposits: ownDeposits)
    }
}

/// A díjak megoszlása egyetlen sávban — a handoff 8 pt magas, 5 pt közű eleme.
struct FeeSplitBar: View {
    let items: [(FeeItem.Kind, Decimal)]

    private var total: Decimal { items.reduce(Decimal(0)) { $0 + $1.1 } }

    private func color(_ kind: FeeItem.Kind) -> Color {
        switch kind {
        case .deposit:    DS.Color.coral
        case .conversion: DS.Color.mint
        case .trade:      DS.Color.lilac
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                HStack(spacing: 5) {
                    ForEach(items, id: \.0) { kind, amount in
                        let share = total > 0 ? (amount / total).doubleValue : 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color(kind))
                            .frame(width: max(geo.size.width * share - 5, 2))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)

            HStack {
                ForEach(items, id: \.0) { kind, _ in
                    Text(kind.rawValue.capitalized)
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.onPlum(0.5))
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
