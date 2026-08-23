import SwiftUI

/// 3a — Kezdőképernyő: teljes vagyon és a platformok egy pillantásra.
struct HomeView: View {
    /// A részletező sáv állapota. Azért ITT él és nem a grafikonban, hogy a
    /// GÖRBÉN KÍVÜLRE koppintva is el lehessen tüntetni — az oda érkező
    /// koppintás a grafikonhoz soha nem jut el.
    @State private var chartScrub: Double?
    /// A görbe kerete. SZÁNDÉKOSAN nem `@State` értéktípus: görgetés közben
    /// minden képkockában változik, és állapotként minden változás
    /// újraépítette volna az egész nézetet — ettől akadt a görgetés.
    /// Osztály-példányba írva a nézet nem épül újra, a koppintás pedig
    /// ugyanúgy friss értéket olvas.
    @State private var chartFrame = FrameBox()

    /// Arányos (lineáris) skála a görbén. Megjegyezzük: aki egyszer
    /// átkapcsolta, az legközelebb is úgy akarja látni.
    @AppStorage("homeChartProportional") private var proportionalChart = false
    @Environment(PortfolioStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: PlatformSummary?
    @State private var movers: [ConstituentMove] = []
    @State private var loadingMovers = true
    @State private var inspecting: ConstituentMove?
    @State private var range: ChartRange = .month
    /// Forintban vagy 100-ra indexálva. A kettő MÁS kérdésre válaszol:
    /// „mennyim van hol" és „melyik teljesített jobban". Eddig az utóbbi
    /// csak a Platformok fülön létezett.
    @State private var indexed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    // iPaden két arányos oszlop: balra a számok és a görbe,
                    // jobbra a platformok és a magyarázatok. Telefonon a
                    // kettő egymás alatt, ugyanebben a sorrendben.
                    // A két oszlop tartalma nagyjából egyforma magas legyen:
                    // balra a számok, a görbe és a magyarázatok, jobbra a
                    // kártyák és a műveletek. Ha a „Mi mozdult" is jobbra
                    // kerülne, a bal oszlop a képernyő felénél elfogyna.
                    AdaptiveColumns(ratio: 0.54, spacing: 26) {
                        balance
                        periodStrip
                        combinedChart
                        digest
                        movements
                    } trail: {
                        if !store.platformSummaries.isEmpty {
                            sectionLabel("Portfóliók")
                            platformCards
                        } else {
                            emptyState
                        }
                        transferWarning
                        estimateNote
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, DS.topPadding)
                // A tab bar RÁÚSZIK a tartalomra — a `safeAreaInset` helyett
                // itt egyszerűbb és megbízhatóbb explicit helyet hagyni neki.
                .padding(.bottom, DS.bottomPadding)
                // Kétoszlopos elrendezésnél kétszer akkora olvasható sáv kell,
                // különben a két oszlop egyenként lenne túl keskeny.
                .readableWidth(sizeClass == .regular ? 1040 : 520)
                .onPreferenceChange(ChartFrameKey.self) { [chartFrame] frame in
                    chartFrame.rect = frame
                }
                // Mellé koppintva eltűnik a részletező sáv. `simultaneous`,
                // hogy a gombokat és a kártyákat NE nyelje el; a görbén
                // belüli koppintást pedig kizárjuk, különben ugyanaz a
                // koppintás egyszerre tenné ki és venné le a sávot.
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .named("home"))
                        .onEnded { value in
                            let frame = chartFrame.rect
                            guard chartScrub != nil, frame != .zero,
                                  !frame.insetBy(dx: -8, dy: -8).contains(value.location)
                            else { return }
                            chartScrub = nil
                        },
                    // Csak amíg van kint sáv. Egy folyamatosan aktív
                    // koppintásfigyelő a görgetés felismerésébe is beleszól.
                    isEnabled: chartScrub != nil
                )
            }
            .coordinateSpace(name: "home")
            .background(DS.Color.canvas)
            // A 58 pt-es felső padding NYELI EL a státuszsáv helyét (handoff).
            // Enélkül a rendszer biztonságos zónája hozzáadódott, és a tartalom
            // ~117 pt-tel lejjebb kezdődött a tervezettnél.
            .ignoresSafeArea(edges: .top)
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selected) { summary in
                PlatformDetailView(summary: summary)
            }
            // Benavigálás, nem lap: teljes magasság + natív vissza-gesztus.
            .sheet(item: $inspecting) { ConstituentDetailView(move: $0) }
            // A MINDIG LÉTEZŐ konténerre kötve: egy feltételes nézeten a
            // `.task` sosem futna le, mert a nézet csak az adat megérkezésekor
            // jön létre — pont az adatra várnánk önmagától.
            .task { await loadMovers() }
        }
        .task { await store.startup() }
    }

    // MARK: - Fejléc

    private var header: some View {
        HStack(spacing: 12) {
            AppMark()

            VStack(alignment: .leading, spacing: 1) {
                Text("Portfólió").font(DS.headerName)
                Text(subtitle)
                    .font(DS.font(11.5, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.5))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Color.ink)
    }

    private var subtitle: String {
        let count = store.platformSummaries.count
        guard let last = store.lastRefresh else {
            return count == 1 ? "1 platform" : "\(count) platform"
        }
        return "\(count) platform · frissítve \(Fmt.time(last))"
    }

    // MARK: - Egyenleg

    private var balance: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Teljes egyenleg")
                .font(DS.label)
                .foregroundStyle(DS.Color.inkSoft(0.5))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Odometer(text: Fmt.huf(store.grandTotalHUF))
                    .foregroundStyle(DS.Color.ink)
                if store.grandDepositsHUF > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Fmt.percent(store.grandGainPct))
                        Text((store.grandGainHUF >= 0 ? "+" : "") + Fmt.huf(store.grandGainHUF))
                            .font(DS.meta)
                    }
                    .font(DS.font(12.5, .medium))
                    .foregroundStyle(store.grandGainPct < 0
                                     ? DS.Color.negativeCream : DS.Color.positiveGreen)
                }
            }
            // Mennyit tettél be összesen. A hozam ehhez képest értendő —
            // enélkül a százalék viszonyítási pont nélkül áll.
            if store.grandDepositsHUF > 0 {
                // A tartozás LEVONÓDIK a fenti összegből; ezt ki is mondjuk,
                // különben a szám és a befizetés nem jön ki egymásból.
                Text(store.liabilitiesHUF > 0
                     ? "Befizetve \(Fmt.huf(store.grandDepositsHUF)) · levonva \(Fmt.huf(store.liabilitiesHUF)) tartozás"
                     : "Befizetve \(Fmt.huf(store.grandDepositsHUF))")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    /// Közös görbe: minden platform külön vonallal, FORINTBAN.
    ///
    /// Az összevetés fülön 100-ra indexált változat van — ott az arányos
    /// elmozdulás a kérdés. Itt az abszolút vagyon, mert a kezdőképernyő
    /// arra válaszol, hogy „mennyim van és miből".
    @ViewBuilder private var combinedChart: some View {
        let series = platformSeries
        if series.isEmpty {
            // Némán eltűnni a legrosszabb: a felhasználó azt hiszi, elromlott.
            chartEmptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                IndexedChart(series: series, guideColor: DS.Color.inkSoft(0.14),
                             axisStart: rangedSnapshots.first?.date,
                             axisEnd: rangedSnapshots.last?.date,
                             format: indexed ? { Fmt.percentPlain($0 - 100) }
                                             : { Fmt.huf(Decimal($0)) },
                             forcedScale: proportionalChart ? .linear : nil,
                             externalScrub: $chartScrub)
                    .frame(height: 120)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ChartFrameKey.self,
                                                   value: proxy.frame(in: .named("home")))
                        }
                    }

                HStack(spacing: 10) {
                    RangeChips(selection: $range, tint: DS.Color.coral,
                               onTint: DS.Color.inkCoral, ink: DS.Color.ink)
                    // Két mérce, egy kapcsolóval: forintban az abszolút
                    // vagyon, indexálva az arányos teljesítmény.
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { indexed.toggle() }
                    } label: {
                        Text(indexed ? "index" : "Ft")
                            .font(DS.font(12, .medium).monospacedDigit())
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 46, height: 30)
                            .pastelCardBackground(in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                // Teljes név, nem monogram: a „T2" kódot a felhasználónak
                // fejben kellene feloldania a saját appjában.
                FlowLayout(spacing: 14, lineSpacing: 6) {
                    ForEach(store.platformSummaries) { summary in
                        HStack(spacing: 5) {
                            Circle().fill(accentColor(summary.platform.accent))
                                .frame(width: 7, height: 7)
                            Text(summary.platform.name)
                                .font(DS.meta)
                                .foregroundStyle(DS.Color.inkSoft(0.6))
                        }
                    }
                    // Néma torzítás nem lehet — és ha már kiírjuk, legyen is
                    // mit tenni ellene. Koppintásra átvált arányos skálára,
                    // ahol a vonalak magassága tényleg a forintokat követi.
                    if CurveBuilder.suggestedScale(series.flatMap(\.values)) == .logarithmic {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { proportionalChart.toggle() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: proportionalChart
                                      ? "arrow.up.and.down" : "function")
                                    .font(.system(size: 9))
                                Text(proportionalChart ? "arányos" : "logaritmikus")
                            }
                            .font(DS.meta)
                            .foregroundStyle(DS.Color.inkSoft(proportionalChart ? 0.6 : 0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Meddig ér vissza a görbe és hány mérésből áll. Enélkül a
                // vonal hossza semmit nem mond az időről.
                chartAxisCaption
                coverageNote
            }
            .padding(.vertical, 2)
        }
    }

    /// A görbe időtengelye szavakban.
    @ViewBuilder private var chartAxisCaption: some View {
        let ordered = rangedSnapshots
        if let first = ordered.first?.date {
            HStack {
                Text(Fmt.day(first))
                Spacer()
                Text("\(ordered.count) mérés" + (indexed ? " · 100-ra indexálva" : ""))
                Spacer()
                Text("ma")
            }
            .font(DS.meta)
            .foregroundStyle(DS.Color.inkSoft(0.4))
        }
    }

    /// Ha egy platform görbéje később kezdődik, mint az ablak, azt kiírjuk.
    ///
    /// Enélkül a felhasználó azt hiszi, a vonal eltűnt vagy hibás — pedig
    /// egyszerűen nincs onnan mérés.
    @ViewBuilder private var coverageNote: some View {
        if let message = coverageMessage {
            Text(message)
                .font(DS.meta)
                .foregroundStyle(DS.Color.inkSoft(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A javítás MÁS a kétféle számlánál: az értékpapír-számla görbéje
    /// visszaszámolható a napi árfolyamokból, a készpénzszámláé viszont csak
    /// kivonatból jöhet. Egy közös mondat az egyiket félrevezetné.
    private var coverageMessage: String? {
        let window = rangedSnapshots
        guard let start = window.first?.date else { return nil }

        func firstMeasurement(_ id: String) -> Date? {
            window.first { $0.byPlatform[id] != nil }?.date
        }

        let late = store.platformSummaries.filter { summary in
            let own = window.filter { $0.byPlatform[summary.platform.id] != nil }
            guard own.count >= 2, let first = own.first?.date else { return false }
            // Egy napnál nagyobb csúszás már látszik a görbén.
            return first.timeIntervalSince(start) > 86_400
        }
        guard !late.isEmpty else { return nil }

        let names = late.map { summary in
            "\(summary.platform.name) (\(Fmt.day(firstMeasurement(summary.platform.id) ?? start)) óta)"
        }
        var remedy: [String] = []
        if late.contains(where: { $0.platform.kind == .brokerage }) {
            remedy.append("az értékpapír-számláét a Beállításokban a „Görbe visszatöltése” pótolja")
        }
        if late.contains(where: { $0.platform.kind == .savings }) {
            remedy.append("a készpénzszámláét a kivonat újbóli beolvasása pótolja")
        }
        return "Nincs mérés az időszak elejére: \(names.joined(separator: ", ")). Ezek közül \(remedy.joined(separator: ", "))."
    }

    /// Miért nincs görbe — és mit lehet tenni érte.
    private var chartEmptyState: some View {
        let points = store.snapshots.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(points <= 1 ? "A görbe a mai naptól épül" : "Még nincs elég mérés a görbéhez")
                .font(DS.font(14, .medium))
            Text(points <= 1
                 ? "Az app naponta rögzít egy mérést, a widget akkor is, ha nem nyitod meg. A Revolut-kivonatok visszamenőleg is hoznak napi adatot — ha még nem olvastad be őket, tedd meg a Beállításokban."
                 : "Platformonként legalább két napi pont kell. Holnap már lesz mit rajzolni.")
                .font(DS.meta)
                .foregroundStyle(DS.Color.inkSoft(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                             opacity: 0.5)
    }

    /// Minden platform UGYANARRA az időtengelyre kerül.
    ///
    /// Korábban csak az értékek listája ment át, és a görbe a sorszám szerint
    /// osztotta el őket a szélességben. A megtakarításnak viszont minden napra
    /// van egyenlege (175 pont), a TBSZ-nek csak kereskedési napokra és csak a
    /// első vásárlástól (55 pont) — így a két vonal ugyanarra a szélességre
    /// feszült, és nem ugyanaz a nap volt egymás alatt. Most a vízszintes hely
    /// a DÁTUMBÓL jön.
    /// A választott időszakra szűkített mérések.
    private var rangedSnapshots: [Snapshot] {
        let all = store.snapshots.sorted { $0.date < $1.date }
        guard let cutoff = range.cutoff else { return all }
        let filtered = all.filter { $0.date >= cutoff }
        // Egyetlen pontból nincs görbe: ilyenkor inkább a teljes sorozat,
        // mint egy üres doboz.
        return filtered.count >= 2 ? filtered : all
    }

    private var platformSeries: [IndexedChart.Series] {
        let ordered = rangedSnapshots
        guard let first = ordered.first?.date, let last = ordered.last?.date else { return [] }
        let span = last.timeIntervalSince(first)
        guard span > 0 else { return [] }

        return store.platformSummaries.compactMap { summary in
            let rows = ordered.compactMap { snapshot -> (x: Double, y: Double)? in
                guard let value = snapshot.byPlatform[summary.platform.id]?.doubleValue
                else { return nil }
                return (snapshot.date.timeIntervalSince(first) / span, value)
            }
            guard rows.count >= 2 else { return nil }
            // Indexálva: mindegyik vonal az időszak ELEJÉHEZ képest 100.
            let values = indexed
                ? rows.map { rows[0].y > 0 ? $0.y / rows[0].y * 100 : 100 }
                : rows.map(\.y)
            return IndexedChart.Series(id: summary.platform.id,
                                       values: values,
                                       color: accentColor(summary.platform.accent),
                                       xs: rows.map(\.x),
                                       label: summary.platform.name)
        }
    }

    private func accentColor(_ accent: Platform.Accent) -> Color { accent.color }

    // MARK: - Napi / heti / havi

    /// Három időszak egy sorban. A százalék mellett MINDIG ott a forint —
    /// a „+0,4%" önmagában nem mondja meg, mennyi pénzről van szó.
    @ViewBuilder private var periodStrip: some View {
        let periods = store.periodChanges
        if !periods.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(periods) { period in
                        periodChip(period)
                    }
                    if periods.count < 3 { Spacer(minLength: 0) }
                }
                if let note = periodNote(periods) {
                    Text(note)
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func periodChip(_ period: Analytics.PeriodChange) -> some View {
        let up = period.gainHUF >= 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(period.span.title)
                    .font(DS.badge)
                    .foregroundStyle(DS.Color.inkSoft(0.5))
                if period.isApproximate {
                    // Nem hallgatjuk el, ha nem pont annyi napot fog át.
                    Text("\(period.actualDays) n")
                        .font(DS.font(9.5, .regular))
                        .foregroundStyle(DS.Color.inkSoft(0.35))
                }
            }
            if period.isPercentMeaningful {
                Text(Fmt.percent(period.pct))
                    .font(DS.font(15, .semibold).monospacedDigit())
                    .foregroundStyle(up ? DS.Color.positiveGreen : DS.Color.negativeCream)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text((up ? "+" : "") + Fmt.huf(period.gainHUF))
                    .font(DS.font(11, .medium).monospacedDigit())
                    .foregroundStyle(DS.Color.inkSoft(0.6))
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                // Nincs értelmes viszonyítási alap — a forint marad, a
                // százalék helyén nem találunk ki semmit.
                Text((up ? "+" : "") + Fmt.huf(period.gainHUF))
                    .font(DS.font(15, .semibold).monospacedDigit())
                    .foregroundStyle(up ? DS.Color.positiveGreen : DS.Color.negativeCream)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("új számla")
                    .font(DS.font(11, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.45))
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: DS.R.chip, style: .continuous),
                             opacity: 0.55)
    }

    /// Mit hagytunk ki, és miért. Enélkül a szám pontosabbnak látszana,
    /// mint amilyen.
    private func periodNote(_ periods: [Analytics.PeriodChange]) -> String? {
        var lines: [String] = []
        if let partial = periods.first(where: \.isPartial) {
            lines.append("A hosszabb időszakok \(partial.coveredPlatforms)/\(partial.totalPlatforms) platformot fognak át — a többinek nincs ilyen régi mérése.")
        }
        if periods.contains(where: { $0.netFlowHUF != 0 }) {
            lines.append("A befizetéseid le vannak vonva: ez a tényleges eredmény, nem az egyenleg változása.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    // MARK: - Ki mozdult nagyot

    /// Napi összefoglaló: kiugró portfólió-mozgás, majd a nap nyertese és
    /// vesztese az alapod nagy tételei közül — hírrel, ha van.
    @ViewBuilder private var digest: some View {
        let entries = DailyDigest.entries(from: movers,
                                          fundValueHUF: store.securitiesValueHUF)
        // Ha bármelyik platform értéke hiányzik vagy hibás, a napi változás
        // értelmetlen — nem kiáltunk ki „−94%-os esést" abból, hogy egy
        // kivonat rosszul olvasódott be. A hiányra a kártyák alatti
        // figyelmeztetés hívja fel a figyelmet.
        let trustworthy = !store.platformSummaries.contains(where: \.isMissingValue)
        let headline = trustworthy ? store.todayChange.flatMap {
            DailyDigest.portfolioHeadline(dayChangePct: $0.pct, dayChangeHUF: $0.gainHUF)
        } : nil
        if loadingMovers || !entries.isEmpty || headline != nil {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Ki mozdult nagyot")
                if let headline {
                    portfolioBanner(headline)
                }
                if loadingMovers && entries.isEmpty {
                    SkeletonRows(count: 2)
                } else if entries.isEmpty {
                    Text("Az alapod nagy tételei közül ma egyik sem mozdult \(Fmt.percentPlain(DailyDigest.moveThreshold))-nál nagyobbat.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                } else {
                    ForEach(entries) { digestRow($0) }
                }
            }
        }
    }

    private func portfolioBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.iconTime)
            Text(text)
                .font(DS.font(12.5, .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }

    private func digestRow(_ entry: DigestEntry) -> some View {
        let winner = entry.kind == .winner
        return Button { inspecting = entry.move } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: winner ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(winner ? DS.Color.iconWinner : DS.Color.iconLoser,
                                in: .rect(cornerRadius: DS.R.rowIcon))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.move.name).font(DS.rowTitle)
                        Text(Fmt.percent(entry.move.changePct))
                            .font(DS.font(12.5, .semibold).monospacedDigit())
                            .foregroundStyle(DS.Color.sign(entry.move.changePct))
                    }
                    // A te pénzeden mennyi ez — ez a szám dönti el,
                    // kell-e vele foglalkozni.
                    Text("Nálad \((entry.impactHUF >= 0 ? "+" : "") + Fmt.huf(entry.impactHUF)) · \(Fmt.percentPlain(entry.move.weightPct)) súly")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.5))
                    if let headline = entry.move.headline {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "newspaper")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Color.iconNews)
                            Text(headline)
                                .font(DS.meta)
                                .foregroundStyle(DS.Color.inkSoft(0.62))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.top, 1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(DS.Color.ink)
    }

    private func loadMovers() async {
        guard let composition = store.knownComposition else {
            loadingMovers = false
            return
        }
        movers = await ConstituentWatcher().snapshot(of: composition)
        loadingMovers = false
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.section)
            .foregroundStyle(DS.Color.inkSoft(0.62))
    }

    // MARK: - Kártyák

    private var platformCards: some View {
        let summaries = store.platformSummaries
        // A kiemelt sötét lap az első ESZKÖZ. Ha valaki a hitelkártyát
        // kézzel előre rendezi, attól a tartozás nem válik hero-kártyává.
        let featuredID = summaries.first { !$0.platform.isLiability }?.id
        return VStack(spacing: 12) {
            ForEach(summaries) { summary in
                Button { selected = summary } label: {
                    PlatformCard(summary: summary, isFeatured: summary.id == featuredID)
                }
                    .buttonStyle(PressableStyle())
            }
            missingDataNote
        }
    }

    /// A kártyán csak annyi fér ki, hogy „hiányzó adat". Az viszont kevés:
    /// megmondjuk, MELYIK platformról van szó és mit lehet tenni érte.
    @ViewBuilder private var missingDataNote: some View {
        let broken = store.platformSummaries.filter(\.isMissingValue)
        if !broken.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 12))
                Text("\(broken.map(\.platform.name).joined(separator: ", ")): az értéke hiányzik vagy hibás, ezért hozamot nem számolok rá. Olvasd be újra a kivonatát — a végösszeg addig is helyes a többi platformra.")
                    .font(DS.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DS.Color.negativeCream)
            .padding(.top, 2)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Még nincs platform")
            Text("Oszd meg ide a Lightyear számlakivonatodat, vagy vegyél fel egy megtakarítási számlát a beállításokban.")
                .font(DS.font(12, .regular))
                .foregroundStyle(DS.Color.inkSoft(0.62))
        }
        .padding(.vertical, 8)
    }

    // MARK: - „Mi mozdult"

    @ViewBuilder private var movements: some View {
        if let split = store.currencySplit {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Mi mozdult")
                movementRow(
                    icon: split.fxHUF >= 0 ? "arrow.up" : "arrow.down",
                    tint: DS.Color.iconFX,
                    title: "A forint mozgása",
                    subtitle: "Devizahatás a befektetett euróra",
                    value: split.fxHUF
                )
                movementRow(
                    icon: split.priceHUF >= 0 ? "arrow.up" : "arrow.down",
                    tint: DS.Color.iconPrice,
                    title: "Az alap árfolyama",
                    subtitle: "Amennyit az ETF ára mozgott",
                    value: split.priceHUF
                )
            }
        }
    }

    private func movementRow(icon: String, tint: Color, title: String,
                             subtitle: String, value: Decimal) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint, in: .rect(cornerRadius: DS.R.rowIcon))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.rowTitle)
                Text(subtitle)
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text((value >= 0 ? "+" : "") + Fmt.huf(value))
                .font(DS.font(13.5, .medium))
                .foregroundStyle(value < 0 ? DS.Color.negativeCream : DS.Color.ink)
        }
        .padding(.vertical, 8)
        .foregroundStyle(DS.Color.ink)
    }

    /// Ha a belső átvezetéseknek hiányzik a párja, a végösszeg hozama torz.
    /// Ezt kimondjuk, nem csendben rossz számot mutatunk.
    @ViewBuilder private var transferWarning: some View {
        if let unmatched = store.unmatchedTransfers {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 12))
                Text("\(Fmt.huf(abs(unmatched.netHUF))) átvezetésnek hiányzik a párja (\(unmatched.accounts.joined(separator: ", "))), ezért a teljes hozam ennyivel pontatlan. Az egyik oldal kivonata hiányzik vagy más időszakról szól — olvasd be a párját AZONOS időszakról, vagy kösd össze azt a számlát a bankkapcsolaton át.")
                    .font(DS.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DS.Color.negativeCream)
            .padding(.vertical, 2)
        }
    }

    /// A becslés nyílt jelzése. Egy vagyonkijelzőnél a becsült és a mért szám
    /// közti különbséget sosem szabad elmosni — itt oda van írva, mennyi a
    /// becsült rész, és hány napja gördül import nélkül.
    @ViewBuilder private var estimateNote: some View {
        // Nulla forint becsült kamatot kiírni értelmetlen: „Ebből 0 Ft becsült
        // kamat" úgy hangzik, mintha hiba volna. Egy nap alatt pár tíz forint
        // gyűlik; ha ennyi sincs, nincs mit jelezni.
        if store.hasEstimatedBalances, store.estimatedInterestHUF >= 1,
           let days = store.oldestEstimateDays, days > 0 {
            let stale = days >= 7
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: stale ? "arrow.clockwise.circle" : "info.circle")
                    .font(.system(size: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ebből \(Fmt.huf(store.estimatedInterestHUF)) becsült kamat")
                        .font(DS.font(11.5, .medium))
                    Text(stale
                         ? "\(days) napja nem olvastál be kivonatot — ideje frissíteni, hogy a becslés visszaigazodjon."
                         : "A megtakarítás egyenlege a mért nettó kulccsal gördül a legutóbbi kivonat óta (\(days) nap).")
                        .font(DS.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(stale ? DS.Color.negativeCream : DS.Color.inkSoft(0.55))
            .padding(.vertical, 2)
        }
    }
}

/// A handoff nyomott állapota: 0,96 skála, 120 ms.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}


/// A kezdőképernyő görbéjének kerete, hogy a „mellé koppintás" felismerhető
/// legyen. Preferenciával megy fel, mert a keretet a gyerek ismeri, a
/// koppintást viszont a szülő kapja el.
private struct ChartFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}


/// Egyszerű doboz a görbe keretének. Osztály, hogy az írása NE számítson
/// nézetváltozásnak — értéktípusként minden görgetett képkocka újraépítést
/// kért volna.
final class FrameBox: @unchecked Sendable {
    var rect: CGRect = .zero
}
