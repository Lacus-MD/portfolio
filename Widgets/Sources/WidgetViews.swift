import SwiftUI
import WidgetKit

/// Egyszerű szikragörbe. Nem Swift Charts: a widgetben egy Path olcsóbb,
/// és tengely nélkül úgysem kell semmi a Charts-ból.
struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = normalized(in: geo.size)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(.linearGradient(colors: [tint.opacity(0.30), tint.opacity(0.02)],
                                          startPoint: .top, endPoint: .bottom))

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = high - low
        // Vízszintes vonal, ha minden érték egyforma — a nullával osztás helyett.
        guard span > 0 else {
            return values.indices.map { index in
                CGPoint(x: size.width * Double(index) / Double(values.count - 1), y: size.height / 2)
            }
        }
        return values.indices.map { index in
            CGPoint(
                x: size.width * Double(index) / Double(values.count - 1),
                y: size.height * (1 - (values[index] - low) / span)
            )
        }
    }
}

/// Az érték-widget: mennyit ér most a portfólió, és merre megy.
struct ValueWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: PortfolioEntry
    /// Csak előnézethez: widgeten kívül nincs értelmes `widgetFamily`.
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var tint: Color { DS.Color.sign(entry.displayGainPct) }

    var body: some View {
        if !entry.hasHoldings {
            emptyState
        } else {
            switch family {
            case .accessoryInline:      inlineView
            case .accessoryCircular:    circularView
            case .accessoryRectangular: rectangularView
            case .systemMedium:         mediumView
            default:                    smallView
            }
        }
    }

    // MARK: - Kezdőképernyő

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            Text(Fmt.compact(entry.valueHUF, currency: "HUF"))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
            gainLine
            Spacer(minLength: 6)
            Sparkline(values: entry.sparkline, tint: tint)
                .frame(height: 26)
        }
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 4)
                Text(Fmt.huf(entry.valueHUF))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(Fmt.huf(entry.valueHUF))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                gainLine
                Spacer(minLength: 6)
                Sparkline(values: entry.sparkline, tint: tint)
                    .frame(height: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.slices.prefix(4)) { slice in
                    HStack(spacing: 5) {
                        Text(slice.name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 2)
                        Text(String(format: "%.0f%%", slice.weight * 100))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Capsule()
                        .fill(DS.Color.accent(slice.accentIndex).opacity(0.18))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(DS.Color.accent(slice.accentIndex))
                                    .frame(width: max(geo.size.width * slice.weight, 2))
                            }
                        }
                }
            }
            .frame(width: 108)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("Portfólió")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if !entry.isLive {
                // Nyílt jelzés: ez nem friss mérés, hanem a legutóbb mentett állapot.
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var gainLine: some View {
        HStack(spacing: 3) {
            Image(systemName: entry.displayGainPct >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(Fmt.percent(entry.displayGainPct))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            // A napi változásnak SAJÁT előjele van: eshet egy olyan napon is,
            // amikor a teljes hozam pluszban áll. A tint átöröklése zöld
            // mínuszt eredményezne — pont a fordítottját annak, ami történt.
            // A kis widgetre nem fér ki, ott elhagyjuk.
            if let day = entry.dayChangeEUR, family != .systemSmall {
                Text("·").foregroundStyle(.secondary)
                Text(Fmt.signedEUR(day))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(DS.Color.sign(day.doubleValue))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tint)
    }

    // MARK: - Zárolási képernyő

    private var inlineView: some View {
        Text("\(Fmt.compact(entry.valueHUF, currency: "HUF")) · \(Fmt.percent(entry.displayGainPct))")
    }

    private var circularView: some View {
        // A mérőgyűrű a hozamot mutatja ±50% skálán — csak nagyságrendnek.
        Gauge(value: min(max(entry.displayGainPct, -50), 50), in: -50...50) {
            Image(systemName: "chart.line.uptrend.xyaxis")
        } currentValueLabel: {
            Text(String(format: "%.0f%%", entry.displayGainPct))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Portfólió").font(.caption2).foregroundStyle(.secondary)
            Text(Fmt.compact(entry.valueHUF, currency: "HUF"))
                .font(.headline.weight(.semibold))
                .widgetAccentable()
            Text("\(Fmt.percent(entry.displayGainPct)) · \(Fmt.compact(entry.valueHUF, currency: "HUF"))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "chart.pie")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DS.Color.coral)
            Text("Nincs pozíció")
                .font(.caption.weight(.medium))
            Text("Nyisd meg az appot")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A megoszlás-widget: melyik alap mekkora szeletet foglal.
struct BreakdownWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: PortfolioEntry
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var visibleCount: Int { family == .systemLarge ? 7 : 3 }

    var body: some View {
        if !entry.hasHoldings {
            ValueWidgetView(entry: entry)
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
                HStack {
                    Text("A számla megoszlása")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .widgetAccentable()
                    Spacer()
                    Text(Fmt.compact(entry.valueHUF, currency: "HUF"))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }

                ForEach(entry.slices.prefix(visibleCount)) { slice in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(slice.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 4)
                            Text(Fmt.percent(slice.gainPercent))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(DS.Color.sign(slice.gainPercent))
                            Text(String(format: "%.1f%%", slice.weight * 100))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.Color.accent(slice.accentIndex).opacity(0.16))
                                Capsule().fill(DS.Color.accent(slice.accentIndex))
                                    .frame(width: max(geo.size.width * slice.weight, 3))
                            }
                        }
                        .frame(height: 4)
                    }
                }

                if entry.slices.count > visibleCount {
                    Text("+\(entry.slices.count - visibleCount) további")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if family == .systemLarge { Spacer(minLength: 0) }
            }
        }
    }
}
