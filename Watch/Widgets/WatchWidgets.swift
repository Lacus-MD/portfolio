import SwiftUI
import WidgetKit

/// Az óra Smart Stack bejegyzései.
///
/// Az óra widgetje NEM kér le árfolyamot: a watchOS-en a hálózat drága, és a
/// telefon úgyis küldi a kész számokat. Ezért a helyben tárolt utolsó
/// állapotot mutatja, és kiírja, mennyire friss.
struct WatchEntry: TimelineEntry {
    var date: Date = Date()
    var summary: WatchSummary = WatchSummary()

    static let sample: WatchEntry = {
        var s = WatchSummary()
        s.totalHUF = 887_909; s.gainPct = 1.38; s.asOf = Date()
        s.spark = [860_000, 868_000, 864_000, 879_000, 884_000, 887_909]
        return WatchEntry(summary: s)
    }()
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? .sample : WatchEntry(summary: WatchStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let entry = WatchEntry(summary: WatchStore.load())
        // Óránként újranézzük a tárolt állapotot; a tényleges frissítést a
        // telefon küldése váltja ki (az reloadAllTimelines-t hív).
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    private var tint: Color {
        entry.summary.gainPct < 0 ? DS.Color.negativeCream : DS.Color.positiveGreen
    }

    private var isStale: Bool {
        guard let asOf = entry.summary.asOf else { return true }
        return Date().timeIntervalSince(asOf) > 6 * 3600
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(Fmt.compact(entry.summary.totalHUF, currency: "HUF")) · \(Fmt.percent(entry.summary.gainPct, digits: 1))")
        case .accessoryCorner:
            Text(Fmt.compact(entry.summary.totalHUF, currency: "HUF"))
                .widgetCurvesContent()
                .widgetLabel { Text(Fmt.percent(entry.summary.gainPct, digits: 1)) }
        case .accessoryCircular:
            Gauge(value: min(max(entry.summary.gainPct, -25), 25), in: -25...25) {
                Image(systemName: "chart.line.uptrend.xyaxis")
            } currentValueLabel: {
                Text(String(format: "%.0f%%", entry.summary.gainPct))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text("Portfólió").font(.system(size: 11)).foregroundStyle(.secondary)
                if isStale {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            Text(Fmt.compact(entry.summary.totalHUF, currency: "HUF"))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .widgetAccentable()
            HStack(spacing: 4) {
                Text(Fmt.percent(entry.summary.gainPct, digits: 1))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                // A mai eredmény — ez az, amiért az ember ránéz az órájára.
                // Ha megvan, ELŐNYT élvez a szikragörbével szemben: egy szám
                // többet mond, mint egy 10 pt magas vonal, és a komplikáció
                // szélessége csak az egyiket bírja el.
                if let today = entry.summary.periods.first(where: { $0.id == 1 }) {
                    Text("· ma \(Fmt.percent(today.pct, digits: 1))")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(today.pct < 0 ? DS.Color.negativeCream : .secondary)
                        .lineLimit(1)
                } else if entry.summary.spark.count >= 2 {
                    WatchSpark(values: entry.summary.spark, tint: tint)
                        .frame(height: 10)
                }
            }
        }
    }
}

struct PortfolioWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PortfolioWatch", provider: WatchProvider()) { entry in
            WatchWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Portfólió")
        .description("A teljes vagyonod és a hozam egy pillantásra.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular,
                            .accessoryInline, .accessoryCorner])
    }
}

@main
struct PortfolioWatchWidgetBundle: WidgetBundle {
    var body: some Widget { PortfolioWatchWidget() }
}
