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

/// A widget saját palettája. A widget-bővítmény külön folyamat, ezért itt az
/// idővonal-bejegyzésben kapott témából és a rendszer világos/sötét módjából
/// építjük fel ugyanazokat a szerepeket, amelyeket az app is használ.
private struct WidgetPalette {
    let theme: AppTheme
    let scheme: ColorScheme

    var card: Color { Color(hex: scheme == .dark ? theme.cardDark : theme.cardLight) }
    var ink: Color { Color(hex: scheme == .dark ? theme.inkDark : theme.inkLight) }
    var secondaryInk: Color { ink.opacity(scheme == .dark ? 0.62 : 0.50) }
    var positive: Color { Color(hex: theme.positive) }
    var negative: Color { Color(hex: theme.negative) }

    func accent(_ index: Int) -> Color {
        guard !theme.accents.isEmpty else { return Color(hex: 0xD09ECB) }
        return Color(hex: theme.accents[index % theme.accents.count])
    }

    func inkOnAccent(_ index: Int) -> Color {
        guard !theme.inkOnAccents.isEmpty else { return ink }
        return Color(hex: theme.inkOnAccents[index % theme.inkOnAccents.count])
    }
}

/// Pénzügyi pillanatkép: a nettó vagyon után azonnal a teljes számlaeloszlást
/// mutatja. A négy pozitív számla pontos összege kifér, a hitelkártya pedig
/// külön, visszafogott tartozássávot kap — nincs félreérthető hozamszázalék,
/// eszközösszesítő vagy +/− ikon.
struct BreakdownWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.colorScheme) private var colorScheme

    let entry: PortfolioEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var palette: WidgetPalette { WidgetPalette(theme: entry.theme, scheme: colorScheme) }

    private var positiveSlices: [PortfolioSlice] {
        entry.slices.filter { !$0.isLiability }.sorted { lhs, rhs in
            let leftRank = accountRank(lhs.kind)
            let rightRank = accountRank(rhs.kind)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.valueHUF > rhs.valueHUF
        }
    }

    private var liabilitySlices: [PortfolioSlice] {
        entry.slices.filter(\.isLiability).sorted { abs($0.valueHUF) > abs($1.valueHUF) }
    }

    private var orderedSlices: [PortfolioSlice] { positiveSlices + liabilitySlices }

    var body: some View {
        Group {
            if !entry.hasHoldings {
                emptyState
            } else if family == .systemLarge {
                largeView
            } else {
                mediumView
            }
        }
        .foregroundStyle(palette.ink)
        .containerBackground(palette.card, for: .widget)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Text(Fmt.huf(entry.valueHUF))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.60)
                .lineLimit(1)
                .padding(.top, 5)

            daySummary
                .padding(.top, 6)

            HStack(alignment: .center, spacing: 14) {
                AllocationRing(slices: orderedSlices, palette: palette)
                    .frame(width: 126, height: 126)
                    .accessibilityLabel("\(entry.slices.count) számla eloszlása")

                VStack(spacing: 4) {
                    ForEach(positiveSlices.prefix(4)) { slice in
                        accountRow(slice, compact: false)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 9)

            if let liability = liabilitySlices.first {
                liabilityRow(liability)
                    .padding(.top, 7)
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Fmt.huf(entry.valueHUF))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                    daySummary
                    if let liability = liabilitySlices.first {
                        Text("\(displayName(liability)) · \(Fmt.huf(abs(liability.valueHUF))) tartozás")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(palette.negative)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AllocationRing(slices: orderedSlices, palette: palette)
                    .frame(width: 72, height: 72)

                VStack(spacing: 3) {
                    ForEach(positiveSlices.prefix(2)) { slice in
                        accountRow(slice, compact: true)
                    }
                }
                .frame(width: 112)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, 5)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("PORTFÓLIÓ")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
            freshnessMark
            Spacer(minLength: 8)
            Text("Frissítve \(Fmt.time(entry.asOf ?? entry.date))")
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(palette.secondaryInk)
    }

    @ViewBuilder private var freshnessMark: some View {
        if entry.isLive {
            Circle()
                .fill(palette.positive)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Friss adat")
        } else {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 8, weight: .semibold))
                .accessibilityLabel("Mentett adat")
        }
    }

    private var daySummary: some View {
        HStack(spacing: 8) {
            if let change = entry.dayChangeHUF {
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("Ma " + (change > 0 ? "+" : "") + Fmt.huf(change))
                        .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(change >= 0 ? palette.positive : palette.negative)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background((change >= 0 ? palette.positive : palette.negative).opacity(0.12),
                            in: Capsule())
            } else {
                Text("Nincs tegnapi mérés")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.secondaryInk)
            }

            Text("nettó vagyon")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(palette.secondaryInk)
        }
    }

    private func accountRow(_ slice: PortfolioSlice, compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .fill(palette.accent(slice.accentIndex))
                Text(slice.monogram)
                    .font(.system(size: compact ? 7 : 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.inkOnAccent(slice.accentIndex))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .padding(3)
            }
            .frame(width: compact ? 22 : 29, height: compact ? 22 : 29)

            if compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName(slice))
                        .font(.system(size: 8.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    Text(Fmt.huf(slice.valueHUF))
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            } else {
                Text(displayName(slice))
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Spacer(minLength: 3)
                Text(Fmt.huf(slice.valueHUF))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 24 : 30, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func liabilityRow(_ slice: PortfolioSlice) -> some View {
        HStack(spacing: 8) {
            Text(displayName(slice))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Fmt.huf(abs(slice.valueHUF))) tartozás")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.negative)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(palette.negative.opacity(colorScheme == .dark ? 0.18 : 0.09),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.pie")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.accent(0))
            Text("Nincs még portfólióadat")
                .font(.caption.weight(.semibold))
            Text("Nyisd meg az appot az első frissítéshez")
                .font(.caption2)
                .foregroundStyle(palette.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayName(_ slice: PortfolioSlice) -> String {
        if slice.kind == .brokerage,
           let first = slice.name.components(separatedBy: "·").first {
            return first.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if slice.kind == .current,
           slice.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "revolut" {
            return "Revolut folyószámla"
        }
        return slice.name
    }

    private func accountRank(_ kind: Platform.Kind) -> Int {
        switch kind {
        case .brokerage: return 0
        case .savings:   return 1
        case .current:   return 2
        case .credit:    return 3
        }
    }
}

/// Szegmenses számlagyűrű. A nagyon kicsi számla is kap egy vékony, látható
/// szeletet, de a középen lévő darabszám mindig a valódi számlaszám.
private struct AllocationRing: View {
    let slices: [PortfolioSlice]
    let palette: WidgetPalette

    var body: some View {
        ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle()
                    .trim(from: segment.start + segment.gap,
                          to: max(segment.start + segment.gap, segment.end - segment.gap))
                    .stroke(palette.accent(slices[index].accentIndex),
                            style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 0) {
                Text("\(slices.count)")
                    .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                Text("számla")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.secondaryInk)
            }
        }
        .padding(12)
    }

    private struct Segment {
        let start: CGFloat
        let end: CGFloat
        let gap: CGFloat
    }

    private var segments: [Segment] {
        guard !slices.isEmpty else { return [] }
        let adjusted = slices.map { max($0.weight, 0.012) }
        let total = adjusted.reduce(0, +)
        guard total > 0 else { return [] }

        var cursor = 0.0
        return adjusted.map { value in
            let fraction = value / total
            let start = cursor
            let end = cursor + fraction
            cursor = end
            return Segment(start: CGFloat(start), end: CGFloat(end),
                           gap: CGFloat(min(0.007, max(fraction * 0.16, 0.0012))))
        }
    }
}
