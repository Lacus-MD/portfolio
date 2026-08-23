import SwiftUI

/// Egy komponens árfolyamgörbéje a kinyitott kártyán.
///
/// A sorozatot a kinyitáskor tölti le, tartományonként, és megjegyzi: a
/// tartomány GLOBÁLIS (a handoff így kéri), tehát ugyanazt a papírt
/// többször ki-be nyitva nem indul újra a hálózat.
struct ConstituentChart: View {
    let symbol: String?
    let range: NewsView.HistoryRange
    /// Az app saját napi mérései, ha nincs Xetra-jegyzés.
    let fallback: [Double]
    let tint: Color

    @State private var closes: [Double] = []
    @State private var loading = true

    private var series: [Double] { closes.count >= 2 ? closes : fallback }

    /// Az időszak hozama a sorozat két végéből. Nem a napi változás — az
    /// fent, a pirulán áll.
    private var periodReturn: Double? {
        guard let first = series.first, let last = series.last, first > 0 else { return nil }
        return (last / first - 1) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if series.count >= 2 {
                AreaChart(points: series, tint: tint, format: { Fmt.eur(Decimal($0)) })
                    .frame(height: 88)
            } else if loading {
                SkeletonBar(width: nil, height: 88)
            } else {
                Text("Ehhez a papírhoz nincs Xetra-jegyzés a történeti forrásban.")
                    .font(DS.font(11, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.36))
                    .frame(height: 88, alignment: .center)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(range.caption)
                    .font(DS.font(10.5, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.36))
                Spacer()
                if let periodReturn, series.count >= 2 {
                    Text(Fmt.percent(periodReturn))
                        .font(DS.font(12.5, .semibold).monospacedDigit())
                        .foregroundStyle(DS.Color.sign(periodReturn))
                }
            }
        }
        .task(id: taskKey) { await load() }
    }

    private var taskKey: String { "\(symbol ?? "-")|\(range.rawValue)" }

    private func load() async {
        guard let symbol else { loading = false; return }
        if let cached = Self.cache[taskKey] { closes = cached; loading = false; return }
        loading = true
        let fetched = (try? await QuoteService().dailyCloses(symbol: symbol, range: range.yahoo))
            .map { $0.map { $0.1.doubleValue } } ?? []
        Self.cache[taskKey] = fetched
        closes = fetched
        loading = false
    }

    /// Egyszerű memóriagyorsítótár. A tartomány globális, a kártyák viszont
    /// ki-be csukódnak; enélkül minden nyitás új hálózati kérés lenne.
    @MainActor private static var cache: [String: [Double]] = [:]
}
