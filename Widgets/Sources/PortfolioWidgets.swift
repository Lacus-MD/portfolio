import SwiftUI
import WidgetKit

struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        // A galéria-előnézet ne lógjon a hálózaton — ott a minta a helyes válasz.
        if context.isPreview { return completion(.placeholder) }
        Task { completion(await PortfolioEntry.make()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        Task {
            let entry = await PortfolioEntry.make()
            // Óránként: a WidgetKit napi büdzséjébe kényelmesen belefér, és egy
            // hosszú távú ETF-portfóliónál ennél sűrűbben nézni úgyis felesleges.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

/// Két külön widget, nem egy konfigurálható: így mindkettő SAJÁT bejegyzésként
/// jelenik meg a widget-galériában. Egy configurable widgetnél előbb hozzá kell
/// adni, majd szerkeszteni, hogy kiderüljön, van másik nézet is.
struct PortfolioValueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PortfolioValue", provider: PortfolioProvider()) { entry in
            ValueWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Portfólió értéke")
        .description("Pontos nettó vagyon, napi változás és portfóliótrend.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryCircular, .accessoryRectangular,
        ])
    }
}

struct PortfolioBreakdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PortfolioBreakdown", provider: PortfolioProvider()) { entry in
            BreakdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Pénzügyi pillanatkép")
        .description("Pontos nettó vagyon, napi változás, számlaegyenlegek és tartozások.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct PortfolioWidgetBundle: WidgetBundle {
    var body: some Widget {
        PortfolioValueWidget()
        PortfolioBreakdownWidget()
    }
}
