import SwiftUI

/// Hírek fül — a 2026-08-22-i „Stock news page redesign" handoff szerint.
///
/// A képernyő két kérdésre válaszol egyszerre, azonos súllyal: mi mozdult ma
/// az alapodban és mennyit számított, illetve van-e hír arról, amit ténylegesen
/// birtokolsz. A korábbi lapos lista mindkettőt elmosta.
///
/// A handoff fix fejlécet ír elő (a szűrőcsipek a képernyő vezérlőfelülete,
/// maradjanak elérhetők), és a saját tab bar-ját a görgetés TESTVÉRÉNEK teszi.
/// Itt a natív `TabView` sávja marad — az az app bevett mintája —, ezért a
/// görgetés alul a `DS.bottomPadding`-gel hagy neki helyet.
struct NewsView: View {
    var isActive = true
    @Environment(PortfolioStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var items: [NewsItem] = []
    @State private var movers: [ConstituentMove] = []
    @State private var loading = true
    /// Az adatcsere nem mozog és nem skálázódik: a betöltött szöveg csak
    /// finoman áttűnik a helyőrzők után.
    @State private var contentVisible = false
    @State private var reading: NewsItem?

    @State private var filter: Filter = .all
    @State private var sort: Sort = .impact
    @State private var expanded: String?
    @State private var range: HistoryRange = .year
    @State private var lastHidden: NewsItem?
    @State private var undoTask: Task<Void, Never>?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Mind", withNews = "Csak hírek", bigMove = "Nagy mozgás"
        var id: String { rawValue }
    }

    enum Sort: Int, CaseIterable {
        case impact, weight, move
        var label: String {
            switch self {
            case .impact: "Hatás szerint"
            case .weight: "Súly szerint"
            case .move:   "Mozgás szerint"
            }
        }
        var next: Sort { Sort(rawValue: (rawValue + 1) % Sort.allCases.count) ?? .impact }
    }

    enum HistoryRange: String, CaseIterable, Identifiable {
        case month = "1H", halfYear = "6H", year = "1É"
        var id: String { rawValue }
        var yahoo: String {
            switch self { case .month: "1mo"; case .halfYear: "6mo"; case .year: "1y" }
        }
        var caption: String {
            switch self {
            case .month: "elmúlt 1 hónap"
            case .halfYear: "elmúlt 6 hónap"
            case .year: "elmúlt 12 hónap"
            }
        }
    }

    private var composition: FundComposition? { store.knownComposition }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    // Négy nagy szekciót érdemes előre felépíteni. A külső
                    // LazyVStack ezeket pont görgetés közben hozta létre,
                    // ezért a sorhatároknál képkockák estek ki. A hosszú,
                    // ismétlődő hírsorok belül továbbra is lusták.
                    VStack(alignment: .leading, spacing: 24) {
                        summaryCard
                        holdingsSection
                        marketSection
                        footnote
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, DS.bottomPadding)
                    .readableWidth(sizeClass == .regular ? 820 : 560)
                }
                .scrollIndicators(.hidden)
                .refreshable { await load() }
            }
            .background(DS.Color.canvas)
            .foregroundStyle(DS.Color.ink)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) { undoToast }
            .sheet(item: $reading) { NewsReader(item: $0) }
        }
        // A TabView a nem kiválasztott füleket is életben tartja. Hírt és
        // képet csak akkor töltünk, amikor a Hírek tényleg látható.
        .task(id: isActive) {
            guard isActive, items.isEmpty else { return }
            await load()
        }
    }

    // MARK: - Fejléc

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.eyebrow.string(from: Date()).uppercased())
                .font(DS.font(10, .semibold))
                .tracking(1.0)
                .foregroundStyle(DS.Color.inkSoft(0.36))
            Text("Hírek")
                .font(DS.font(29, .semibold))
                .padding(.top, 1)

            // A csipek a képernyő vezérlőfelülete, ezért a FIX fejlécben
            // ülnek: görgetés közben is elérhetők maradnak.
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Filter.allCases) { option in
                        chip(option.rawValue, active: filter == option) {
                            withAnimation(.snappy(duration: 0.2)) { filter = option }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 12)

            Rectangle().fill(DS.Color.inkSoft(0.075)).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, DS.topPadding)
    }

    /// Az aktív csip a SZÖVEGSZÍNT fordítja meg, nem az akcentust használja.
    /// A handoff színfegyelme szerint az akcentus a nem-irányjelző felületé
    /// (súlysáv, aktív tartomány, hír-vonal); ha a szűrő is azt vinné, a kettő
    /// versengene.
    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.font(12, .semibold))
                .foregroundStyle(active ? DS.Color.canvas : DS.Color.inkSoft(0.6))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(active ? DS.Color.ink : DS.Color.card)
                        .overlay(Capsule().stroke(active ? .clear : DS.Color.inkSoft(0.075)))
                }
        }
        .buttonStyle(.plain)
    }

    private static let eyebrow: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "hu_HU")
        f.dateFormat = "EEEE, MMMM d."
        return f
    }()

    // MARK: - Összegző kártya

    @ViewBuilder private var summaryCard: some View {
        if !movers.isEmpty {
            let gains = movers.filter { $0.contributionPct > 0 }
                .reduce(0.0) { $0 + $1.contributionPct }
            let losses = movers.filter { $0.contributionPct < 0 }
                .reduce(0.0) { $0 - $1.contributionPct }
            let net = gains - losses
            let weight = movers.reduce(0.0) { $0 + $1.weightPct }
            let scale = max(gains, losses)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("AZ ALAPOD MA")
                        .font(DS.font(10, .semibold)).tracking(1.0)
                        .foregroundStyle(DS.Color.inkSoft(0.36))
                    Spacer()
                    Text("\(movers.count) tétel · \(Fmt.percentPlain(weight)) súly")
                        .font(DS.font(11, .medium).monospacedDigit())
                        .foregroundStyle(DS.Color.inkSoft(0.36))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.percent(net, digits: 2))
                        .font(DS.font(33, .semibold).monospacedDigit())
                        .foregroundStyle(DS.Color.sign(net))
                    Text("nettó hozzájárulás az alapon")
                        .font(DS.font(12, .regular))
                        .foregroundStyle(DS.Color.inkSoft(0.6))
                        .frame(maxWidth: 140, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 5)
                .padding(.bottom, 13)

                // Kétoldalas sáv: a hosszabbik oldal 100%, a másik arányos.
                // Így a két nyers összeg viszonya látszik, nem csak a nettó.
                HStack(spacing: 5) {
                    HStack {
                        Spacer(minLength: 0)
                        Capsule().fill(DS.Color.negativeCream)
                            .frame(width: nil, height: 9)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(x: scale > 0 ? losses / scale : 0, anchor: .trailing)
                    }
                    Rectangle().fill(DS.Color.inkSoft(0.36)).frame(width: 1, height: 15)
                    HStack {
                        Capsule().fill(DS.Color.positiveGreen)
                            .frame(height: 9)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(x: scale > 0 ? gains / scale : 0, anchor: .leading)
                        Spacer(minLength: 0)
                    }
                }
                HStack {
                    Text("\(Fmt.percent(-losses, digits: 2)) elvéve")
                        .foregroundStyle(DS.Color.negativeCream)
                    Spacer()
                    Text("\(Fmt.percent(gains, digits: 2)) hozzáadva")
                        .foregroundStyle(DS.Color.positiveGreen)
                }
                .font(DS.font(11.5, .medium).monospacedDigit())
                .padding(.top, 7)
            }
            .padding(EdgeInsets(top: 15, leading: 16, bottom: 14, trailing: 16))
                .pastelCardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Color.inkSoft(0.075)))
                .opacity(contentVisible ? 1 : 0)
        } else if loading {
            SkeletonBar(width: nil, height: 118)
        }
    }

    // MARK: - Tételek

    private var visibleMovers: [ConstituentMove] {
        let sorted: [ConstituentMove]
        switch sort {
        case .impact: sorted = movers.sorted { abs($0.contributionPct) > abs($1.contributionPct) }
        case .weight: sorted = movers.sorted { $0.weightPct > $1.weightPct }
        case .move:   sorted = movers.sorted { abs($0.changePct) > abs($1.changePct) }
        }
        switch filter {
        case .all:      return sorted
        case .withNews: return sorted.filter { !news(for: $0).isEmpty }
        case .bigMove:  return sorted.filter { abs($0.changePct) >= 1 }
        }
    }

    @ViewBuilder private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("LEGNAGYOBB TÉTELEID") {
                Button { withAnimation(.snappy(duration: 0.2)) { sort = sort.next } } label: {
                    HStack(spacing: 3) {
                        Text(sort.label)
                        Image(systemName: "arrow.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(DS.font(11, .medium))
                    .foregroundStyle(DS.Color.inkSoft(0.6))
                }
                .buttonStyle(.plain)
            }

            if loading && movers.isEmpty {
                SkeletonRows(count: 4)
            } else if visibleMovers.isEmpty {
                Text(filter == .withNews
                     ? "Ma egyik tételedről sincs hír. Ez a szokásos: nyolc papírról nem jelenik meg minden nap valami."
                     : "Ma egyik tételed sem mozdult 1%-nál nagyobbat.")
                    .font(DS.font(12, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .opacity(contentVisible ? 1 : 0)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleMovers) { mover in
                        VStack(alignment: .leading, spacing: 6) {
                            holdingCard(mover)
                            ForEach(news(for: mover)) { item in
                                attachedNews(item, accent: DS.Color.coral)
                            }
                        }
                    }
                }
                .opacity(contentVisible ? 1 : 0)
            }
        }
    }

    private func sectionHeader<Trailing: View>(_ title: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(DS.font(10, .semibold)).tracking(1.0)
                .foregroundStyle(DS.Color.inkSoft(0.36))
                .lineLimit(1).fixedSize()
            Rectangle().fill(DS.Color.inkSoft(0.075)).frame(height: 1)
            trailing()
        }
    }

    private func holdingCard(_ mover: ConstituentMove) -> some View {
        let open = expanded == mover.name
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    expanded = open ? nil : mover.name
                }
            } label: {
                VStack(spacing: 11) {
                    HStack(spacing: 11) {
                        monogram(mover)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mover.name)
                                .font(DS.font(16, .semibold))
                                .lineLimit(1)
                            if let ticker = mover.ticker {
                                Text(ticker)
                                    .font(DS.font(11, .medium).monospacedDigit())
                                    .tracking(0.4)
                                    .foregroundStyle(DS.Color.inkSoft(0.36))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(Fmt.decimal(mover.price, min: 2, max: 2))
                                    .font(DS.font(16, .semibold).monospacedDigit())
                                Text("EUR")
                                    .font(DS.font(10, .medium))
                                    .foregroundStyle(DS.Color.inkSoft(0.36))
                            }
                            Text(Fmt.percent(mover.changePct))
                                .font(DS.font(11.5, .semibold).monospacedDigit())
                                .foregroundStyle(DS.Color.sign(mover.changePct))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(DS.Color.sign(mover.changePct).opacity(0.14),
                                            in: .rect(cornerRadius: 6))
                        }
                    }
                    weightRow(mover)
                }
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if open { expandedChart(mover) }
        }
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Color.inkSoft(0.075)))
        .foregroundStyle(DS.Color.ink)
    }

    /// Helyőrző a cég logója helyén. Valódi logót nem teszünk bele: ahhoz
    /// harmadik fél védjegyeit kellene a csomagba tenni, ami engedélyhez kötött.
    private func monogram(_ mover: ConstituentMove) -> some View {
        Text(String(mover.name.prefix(2)).uppercased())
            .font(DS.font(11, .semibold)).tracking(0.2)
            .foregroundStyle(DS.Color.inkSoft(0.6))
            .frame(width: 38, height: 38)
            .background(DS.Color.inkSoft(0.06), in: .rect(cornerRadius: 11))
    }

    /// Súly sávként. A két százalék korábban magyarázat nélkül állt egymás
    /// mellett; a sáv adja meg a viszonyítást, a felirat pedig megmondja,
    /// melyik melyik.
    private func weightRow(_ mover: ConstituentMove) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.inkSoft(0.10))
                    Capsule().fill(DS.Color.coral)
                        // 5% a skála teteje: a legnagyobb valódi súly 4,4%.
                        .frame(width: geo.size.width * min(mover.weightPct / 5, 1))
                }
            }
            .frame(height: 4)
            HStack(spacing: 0) {
                Text("súly ").foregroundStyle(DS.Color.inkSoft(0.36))
                Text(Fmt.percentPlain(mover.weightPct))
                    .foregroundStyle(DS.Color.inkSoft(0.6))
                Spacer()
                Text("az alapon ").foregroundStyle(DS.Color.inkSoft(0.36))
                Text(Fmt.percent(mover.contributionPct, digits: 2))
                    .font(DS.font(10.5, .semibold).monospacedDigit())
                    .foregroundStyle(DS.Color.sign(mover.contributionPct))
            }
            .font(DS.font(10.5, .regular).monospacedDigit())
        }
    }

    // MARK: - Kinyitott görbe

    @ViewBuilder private func expandedChart(_ mover: ConstituentMove) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(DS.Color.inkSoft(0.075)).frame(height: 1)
                .padding(.bottom, 5)
            HStack(spacing: 5) {
                ForEach(HistoryRange.allCases) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { range = option }
                    } label: {
                        Text(option.rawValue)
                            .font(DS.font(11, .semibold).monospacedDigit())
                            .foregroundStyle(range == option ? DS.Color.coral : DS.Color.inkSoft(0.36))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(range == option ? DS.Color.coral.opacity(0.17) : .clear,
                                        in: .rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            ConstituentChart(symbol: mover.xetra, range: range,
                             fallback: mover.history,
                             tint: DS.Color.sign(mover.changePct))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Hírek

    private func news(for mover: ConstituentMove) -> [NewsItem] {
        let matched = items.filter { $0.holding == mover.name }
        let extra: NewsItem? = mover.headline.flatMap { headline in
            guard let link = mover.link,
                  !matched.contains(where: { $0.link == link }) else { return nil }
            return NewsItem(title: headline, link: link, source: "Google News",
                            reason: .holding, holding: mover.name)
        }
        return ([extra].compactMap { $0 } + matched)
            .filter { !store.hiddenNews.contains($0.link) }
            .prefix(3)
            .map { $0 }
    }

    /// A behúzás teszi alárendeltté, a bal oldali akcentusvonal pedig
    /// összeköti a fölötte lévő papírral.
    private func attachedNews(_ item: NewsItem, accent: Color) -> some View {
        Button { reading = item } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(DS.font(14, .semibold))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                if let summary = item.summary {
                    Text(summary)
                        .font(DS.font(12, .regular))
                        .lineSpacing(2)
                        .foregroundStyle(DS.Color.inkSoft(0.6))
                        .multilineTextAlignment(.leading)
                }
                Text(meta(item))
                    .font(DS.font(10.5, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.36))
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13))
            .pastelCardBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) { accent.frame(width: 2) }
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Color.inkSoft(0.075)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Color.ink)
        .padding(.leading, 14)
        .swipeToHide { hide(item) }
    }

    // MARK: - Piaci hírek

    private var generalItems: [NewsItem] {
        let shown = Set(movers.map(\.name))
        return items.filter { item in
            guard !store.hiddenNews.contains(item.link) else { return false }
            guard let holding = item.holding else { return true }
            return !shown.contains(holding)
        }
    }

    @ViewBuilder private var marketSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("PIACI HÍREK") { EmptyView() }
            if generalItems.isEmpty && loading {
                SkeletonRows(count: 3).padding(.top, 8)
            } else if generalItems.isEmpty {
                Text("Most nincs olyan hír, ami a forintot vagy a piacot érintené. Csak azt mutatjuk, ami a te portfóliódra hat.")
                    .font(DS.font(12, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .opacity(contentVisible ? 1 : 0)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(generalItems.prefix(12)) { item in
                        Button { reading = item } label: { marketRow(item) }
                            .buttonStyle(.plain)
                            .foregroundStyle(DS.Color.ink)
                    }
                }
                .opacity(contentVisible ? 1 : 0)
            }
        }
    }

    private func marketRow(_ item: NewsItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .font(DS.font(13.5, .semibold))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                    if let summary = item.summary {
                        Text(summary)
                            .font(DS.font(12, .regular))
                            .lineSpacing(2)
                            .foregroundStyle(DS.Color.inkSoft(0.6))
                            .multilineTextAlignment(.leading)
                            .padding(.top, 4)
                    }
                    Text(meta(item))
                        .font(DS.font(10.5, .regular))
                        .foregroundStyle(DS.Color.inkSoft(0.36))
                        .padding(.top, 7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                thumbnail(item)
            }
            .padding(.vertical, 12)
            Rectangle().fill(DS.Color.inkSoft(0.075)).frame(height: 1)
        }
        .contentShape(.rect)
    }

    /// A csatorna vezető képe, ha ad. Ha nem, csíkos helyőrző — kitalált
    /// képet nem teszünk oda.
    @ViewBuilder private func thumbnail(_ item: NewsItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        if let raw = item.imageURL, let url = URL(string: raw) {
            CachedNewsThumbnail(url: url)
            .frame(width: 52, height: 52)
            .clipShape(shape)
        } else {
            shape.fill(DS.Color.inkSoft(0.06)).frame(width: 52, height: 52)
        }
    }

    private var footnote: some View {
        Text("Koppints egy tételre a görbéjéhez")
            .font(DS.font(10.5, .regular))
            .foregroundStyle(DS.Color.inkSoft(0.36))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Elrejtés és visszavonás

    private func hide(_ item: NewsItem) {
        store.hideNews(item.link)
        lastHidden = item
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .milliseconds(4200))
            guard !Task.isCancelled else { return }
            withAnimation { lastHidden = nil }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if let hidden = lastHidden {
            HStack {
                Text("Hír elrejtve")
                    .font(DS.font(12.5, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.6))
                Spacer()
                Button("Visszavonás") {
                    store.unhideNews(hidden.link)
                    undoTask?.cancel()
                    withAnimation { lastHidden = nil }
                }
                .font(DS.font(12.5, .semibold))
                .foregroundStyle(DS.Color.coral)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Color.inkSoft(0.075)))
            .padding(.horizontal, 14)
            .padding(.bottom, 104)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Adat

    private func meta(_ item: NewsItem) -> String {
        var parts = [item.source]
        switch item.reason {
        case .holding: parts.append("az alapod egyik nagy tételéről")
        case .forint:  parts.append("a forintodat érinti")
        case .market:  parts.append("a piacot érinti")
        }
        if item.language != "hu" { parts.append("angolul") }
        if let date = item.date { parts.append(Fmt.time(date)) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        let shouldFadeIn = items.isEmpty && movers.isEmpty
        if shouldFadeIn { contentVisible = false }
        loading = true
        // MainActor-állapotot a párhuzamos feladatok elindítása ELŐTT
        // másolunk ki; így a háttérfeladat nem nyúl SwiftUI-állapothoz.
        let currentComposition = composition
        async let feed = NewsService().fetch(limit: 40)
        async let moved: [ConstituentMove] = {
            guard let currentComposition else { return [] }
            return await ConstituentWatcher().snapshot(of: currentComposition)
        }()
        // Együtt cseréljük le a két helyőrző-adathalmazt. Ha a feed előbb
        // ért vissza, korábban eltűnhetett a skeleton, miközben a tételekre
        // még vártunk — ez egy rövid üres villanást okozott a fade előtt.
        let (fetchedItems, fetchedMovers) = await (feed, moved)
        items = fetchedItems
        movers = fetchedMovers
        NewsImagePreloader.shared.prefetch(
            items.compactMap { $0.imageURL.flatMap(URL.init(string:)) }
        )
        loading = false
        if shouldFadeIn {
            // Adjunk egy renderkört az új elrendezésnek láthatatlanul. Így
            // nem a kártyák helye/mérete animálódik (popup-hatás), csak az
            // opacitásuk indul el a következő képkockán.
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.easeInOut(duration: 0.38)) { contentVisible = true }
        } else {
            contentVisible = true
        }
        NewsPrewarmer.prewarm(items)
    }
}

/// A decoded thumbnail that never performs image work in the scroll view's
/// render pass. The preloader fills the cache as soon as the feed arrives.
private struct CachedNewsThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                DS.Color.inkSoft(0.06)
            }
        }
        .task(id: url) {
            image = await NewsImagePreloader.shared.load(url)
        }
    }
}

/// Balra húzva elrejt. Jobbra húzva nem történik semmi, és a függőleges
/// görgetés végig működik — a küszöb alatt visszaugrik.
private struct SwipeToHide: ViewModifier {
    let onHide: () -> Void
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(DS.Color.negativeCream.opacity(0.16))
                    .overlay(alignment: .trailing) {
                        Text("Elrejtés")
                            .font(DS.font(11, .semibold))
                            .foregroundStyle(DS.Color.negativeCream)
                            .padding(.trailing, 16)
                    }
                    .padding(.leading, 14)
                    .opacity(offset < -8 ? 1 : 0)
            }
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height)
                        else { return }
                        offset = min(0, value.translation.width)
                    }
                    .onEnded { _ in
                        if offset < -84 {
                            withAnimation(.easeOut(duration: 0.2)) { offset = -400 }
                            onHide()
                        } else {
                            withAnimation(.spring(duration: 0.22)) { offset = 0 }
                        }
                    }
            )
    }
}

private extension View {
    func swipeToHide(_ action: @escaping () -> Void) -> some View {
        modifier(SwipeToHide(onHide: action))
    }
}
