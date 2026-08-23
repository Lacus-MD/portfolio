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
            Text(Fmt.huf(entry.valueHUF))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.48)
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
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
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
            if let day = entry.dayChangeHUF, family != .systemSmall {
                Text("·").foregroundStyle(.secondary)
                Text((day >= 0 ? "+" : "") + Fmt.huf(day))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(DS.Color.sign(day.doubleValue))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tint)
    }

    // MARK: - Zárolási képernyő

    private var inlineView: some View {
        Text("\(Fmt.huf(entry.valueHUF)) · \(Fmt.percent(entry.displayGainPct))")
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
            Text(Fmt.huf(entry.valueHUF))
                .font(.headline.weight(.semibold))
                .widgetAccentable()
            Text(entry.dayChangeHUF.map { "Ma " + ($0 >= 0 ? "+" : "") + Fmt.huf($0) }
                 ?? Fmt.percent(entry.displayGainPct))
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

/// Pénzügyi pillanatkép: pontos nettó vagyon, napi változás, számlaegyenlegek
/// és tartozások. A korábbi „megoszlás" nézet sok üres helyet hagyott, csak
/// rövidített végösszeget írt ki, és a folyószámlára hamis hozamot számolt.
struct BreakdownWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: PortfolioEntry
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var visibleCount: Int { family == .systemLarge ? 5 : 3 }
    private var movementColor: Color {
        DS.Color.sign(entry.dayChangeHUF?.doubleValue ?? entry.displayGainPct)
    }

    var body: some View {
        if !entry.hasHoldings {
            ValueWidgetView(entry: entry)
        } else if family == .systemLarge {
            largeView
        } else {
            mediumView
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 11) {
            hero

            HStack(alignment: .firstTextBaseline) {
                Text("SZÁMLÁK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.slices.count) egyenleg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(entry.slices.prefix(visibleCount)) { slice in
                    accountRow(slice, compact: false)
                }
            }

            Spacer(minLength: 0)
            if entry.liabilitiesHUF > 0 {
                HStack(spacing: 5) {
                    Label(Fmt.huf(entry.grossAssetsHUF), systemImage: "plus.circle.fill")
                        .foregroundStyle(DS.Color.positiveGreen)
                    Spacer(minLength: 4)
                    Label("−" + Fmt.huf(entry.liabilitiesHUF),
                          systemImage: "minus.circle.fill")
                        .foregroundStyle(DS.Color.negativeCream)
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
            }
        }
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("NETTÓ VAGYON")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    freshnessIcon
                }
                Text(Fmt.huf(entry.valueHUF))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .widgetAccentable()
                dayChange
                Spacer(minLength: 2)
                Sparkline(values: entry.sparkline, tint: movementColor)
                    .frame(height: 38)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(entry.slices.prefix(visibleCount)) { slice in
                    accountRow(slice, compact: true)
                }
            }
            .frame(width: 154)
        }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.linearGradient(
                    colors: [DS.Color.coral.opacity(0.25),
                             DS.Color.lilac.opacity(0.18),
                             DS.Color.mint.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("NETTÓ VAGYON")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)
                    freshnessIcon
                    Spacer()
                    Text(Fmt.time(entry.asOf ?? entry.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(Fmt.huf(entry.valueHUF))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .widgetAccentable()
                HStack(alignment: .bottom) {
                    dayChange
                    Spacer(minLength: 10)
                    Sparkline(values: entry.sparkline, tint: movementColor)
                        .frame(width: 112, height: 38)
                }
            }
            .padding(14)
        }
        .frame(height: 122)
    }

    @ViewBuilder private var freshnessIcon: some View {
        if entry.isLive {
            Circle().fill(DS.Color.positiveGreen).frame(width: 5, height: 5)
        } else {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
    }

    private var dayChange: some View {
        let change = entry.dayChangeHUF
        return HStack(spacing: 4) {
            Image(systemName: (change ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(change.map { "Ma " + ($0 >= 0 ? "+" : "") + Fmt.huf($0) }
                 ?? "Még nincs tegnapi mérés")
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(change == nil ? Color.secondary : movementColor)
    }

    private func accountRow(_ slice: PortfolioSlice, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Circle()
                    .fill(DS.Color.accent(slice.accentIndex))
                    .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(slice.name)
                        .font((compact ? Font.caption2 : .caption).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(accountMeaning(slice))
                        .font(.system(size: compact ? 8 : 9))
                        .foregroundStyle(slice.isLiability
                                         ? DS.Color.negativeCream : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                Text(Fmt.huf(slice.valueHUF))
                    .font((compact ? Font.caption2 : .caption).weight(.bold).monospacedDigit())
                    .foregroundStyle(slice.isLiability ? DS.Color.negativeCream : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.accent(slice.accentIndex).opacity(0.13))
                    Capsule().fill(DS.Color.accent(slice.accentIndex))
                        .frame(width: max(geo.size.width * slice.weight, 2))
                }
            }
            .frame(height: compact ? 2.5 : 3)
        }
    }

    private func accountMeaning(_ slice: PortfolioSlice) -> String {
        if slice.isLiability { return "tartozás · \(Fmt.percentPlain(slice.weight * 100))" }
        if slice.isTransactional { return "folyószámla · \(Fmt.percentPlain(slice.weight * 100))" }
        if let gain = slice.gainPercent {
            return "\(Fmt.percent(gain)) · \(Fmt.percentPlain(slice.weight * 100))"
        }
        return Fmt.percentPlain(slice.weight * 100)
    }
}
