import SwiftUI

/// Egy komponens részletei: ár, napi mozgás, súly és a gyűjtött görbe.
///
/// A **súly** mindig ott van a szám mellett: egy 3%-os Apple-mozgás az alapodat
/// 0,12%-kal mozdítja. Enélkül a százalék sokkal fontosabbnak látszik, mint
/// amennyi a te pénzedre nézve.
struct ConstituentDetailView: View {
    let move: ConstituentMove
    @Environment(\.dismiss) private var dismiss
    @State private var reading: NewsItem?
    /// A Yahoo-tól letöltött történeti záróárak. Amíg üres, az app által
    /// gyűjtött napi mérések látszanak.
    @State private var history: [Double] = []
    @State private var historyDates: [Date] = []
    @State private var historyRange: String?
    @State private var loadingHistory = true

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    price
                    chart
                    facts
                    if let headline = move.headline, let link = move.link {
                        newsBlock(headline: headline, link: link)
                    }
                }
                .padding(20)
                .readableWidth()
            }
            .background(DS.Color.canvas)
            .foregroundStyle(DS.Color.ink)
            .navigationTitle(move.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kész") { dismiss() }
                }
            }
            .sheet(item: $reading) { NewsReader(item: $0) }
            .task { await loadHistory() }
        }
        .tint(DS.Color.coral)
    }

    private var price: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Árfolyam a Xetrán")
                .font(DS.label).foregroundStyle(DS.Color.inkSoft(0.5))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.eur(move.price))
                    .font(DS.font(32, .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: move.changePct >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(Fmt.percent(move.changePct))
                        .font(DS.font(14, .semibold).monospacedDigit())
                }
                .foregroundStyle(DS.Color.sign(move.changePct))
            }
        }
    }

    /// A megjelenített görbe: elsősorban a letöltött TÖRTÉNETI sorozat,
    /// másodsorban az app saját napi mérései.
    private var series: [Double] { history.count >= 2 ? history : move.history }

    @ViewBuilder private var chart: some View {
        if series.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                AreaChart(points: series, tint: DS.Color.sign(move.changePct),
                          dates: history.count >= 2 ? historyDates : [],
                          format: { Fmt.eur(Decimal($0)) })
                    .frame(height: 140)
                Text(historyRange ?? "\(series.count) napi mérés — az app gyűjti")
                    .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.45))
            }
        } else if loadingHistory {
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: nil, height: 140)
                SkeletonBar(width: 150, height: 9, delay: 0.1)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("A görbe a mai naptól épül")
                    .font(DS.font(15, .medium))
                Text("Ehhez a papírhoz nincs Xetra-jegyzés a történeti forrásban, ezért az app naponta maga méri. Holnaptól lesz mit rajzolni.")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
    }

    /// Egy éves napi záróár-sorozat a Xetráról — ugyanabban a pénznemben,
    /// mint a fejlécben álló ár, hogy a kettő összeérjen.
    private func loadHistory() async {
        defer { loadingHistory = false }
        guard let symbol = move.xetra else { return }
        guard let closes = try? await QuoteService().dailyCloses(symbol: symbol, range: "1y"),
              closes.count >= 2 else { return }
        history = closes.map { $0.1.doubleValue }
        historyDates = closes.map(\.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "hu_HU")
        formatter.dateFormat = "yyyy. MMM d."
        if let first = closes.first?.0 {
            historyRange = "\(formatter.string(from: first)) óta · \(closes.count) kereskedési nap"
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            row("Súly az alapban", Fmt.percentPlain(move.weightPct))
            Divider().padding(.leading, 16)
            row("Hatás az alapra ma", Fmt.percent(move.contributionPct, digits: 2))
        }
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(DS.rowTitle)
            Spacer()
            Text(value).font(DS.font(13.5, .medium).monospacedDigit())
        }
        .padding(16)
    }

    private func newsBlock(headline: String, link: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Friss hír").font(DS.section).foregroundStyle(DS.Color.inkSoft(0.62))
            Button {
                reading = NewsItem(title: headline, link: link,
                                   source: "Google News", reason: .holding)
            } label: {
                Text(headline)
                    .font(DS.font(13, .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Color.ink)
        }
    }
}
