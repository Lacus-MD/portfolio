import SwiftUI

/// Időszak-választó. A handoff négy egyenlő chipet ír elő, pontosan egy aktív.
enum ChartRange: String, CaseIterable, Identifiable {
    case week, month, quarter, max
    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "7N"; case .month: "30N"; case .quarter: "3H"; case .max: "MAX"
        }
    }

    var cutoff: Date? {
        let calendar = Calendar.current
        switch self {
        case .week:    return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month:   return calendar.date(byAdding: .day, value: -30, to: Date())
        case .quarter: return calendar.date(byAdding: .month, value: -3, to: Date())
        case .max:     return nil
        }
    }
}

struct RangeChips: View {
    @Binding var selection: ChartRange
    var tint: Color = DS.Color.coral
    var onTint: Color = .white
    /// A NEM kiválasztott chipek szövegszíne.
    ///
    /// Korábban fixen `onShell()` volt, ami sötét héjon fehér — a
    /// kezdőképernyő viszont a VÁSZNON ül, és világos módban ott a fehér
    /// szöveg láthatatlan az üveggombon. A hívó tudja, min ül a sáv.
    var ink: Color = DS.Color.ink

    var body: some View {
        HStack(spacing: 9) {
            ForEach(ChartRange.allCases) { range in
                let active = range == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = range } } label: {
                    Text(range.label)
                        .font(DS.font(12, active ? .medium : .regular))
                        .foregroundStyle(active ? onTint : ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .contentShape(.rect(cornerRadius: DS.R.chip))
                        // Az aktív chip a platform színét viseli, az inaktívak
                        // natív üveget — így a kiválasztás egyértelmű marad,
                        // de a sáv nem lesz nehéz.
                        .glassEffect(
                            active
                                ? .regular.tint(tint).interactive()
                                : .regular.interactive(),
                            in: .rect(cornerRadius: DS.R.chip)
                        )
                }
                .buttonStyle(PressableStyle())
            }
        }
        .foregroundStyle(ink)
    }
}

/// Pont a görbe végén: „itt tartunk most".
///
/// Korábban a külső kör `repeatForever` animációval lüktetett. A `TabView`
/// az első fület a többi mögött is életben tartja, ezért ez az animáció a
/// Hírek, Kiadások és Beállítások görgetése közben is folyamatos kompozitálást
/// kért a GPU-tól. A statikus, halvány glória ugyanazt a jelentést őrzi meg,
/// állandó képkockaterhelés nélkül.
struct PulsingDot: View {
    var color: Color
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: size * 1.85, height: size * 1.85)
            Circle()
                .fill(DS.Color.onShell())
                .stroke(color, lineWidth: size * 0.25)
                .frame(width: size, height: size)
        }
    }
}

/// Sima görbe + lefelé halványodó terület — a 3c fő ábrája.
struct AreaChart: View {
    let points: [Double]
    let tint: Color
    var valueTag: String?
    /// Ügyletjelölők: a sorozat indexe → irány.
    var markers: [Int: TradeMarker.Kind] = [:]
    /// A pontokhoz tartozó napok. Ha üres, nincs mit kiírni, és a sáv sem
    /// jelenik meg — nem találunk ki dátumot a sorszámból.
    var dates: [Date] = []
    /// Hogyan írjuk ki az értéket. Alapból forint; a komponens-görbe euró.
    var format: (Double) -> String = { Fmt.huf(Decimal($0)) }

    @State private var drawn = false
    @State private var scrub: Double?

    /// A használt skála — a hívó ebből tudja, kell-e jelzést kiírnia.
    var scale: CurveBuilder.Scale { CurveBuilder.suggestedScale(points) }

    /// Simítási ablak; 1 = nincs simítás.
    var window: Int { CurveBuilder.suggestedWindow(points.count) }
    var isSmoothed: Bool { window > 1 }

    private var drawnPoints: [Double] {
        CurveBuilder.smoothed(points, window: window)
    }

    var body: some View {
        GeometryReader { geo in
            let values = drawnPoints
            let path = CurveBuilder.path(values, in: geo.size, scale: scale)
            ZStack(alignment: .topLeading) {
                // Szaggatott vezetővonal a magasság 38%-ánál.
                Path { p in
                    p.move(to: .init(x: 0, y: geo.size.height * 0.38))
                    p.addLine(to: .init(x: geo.size.width, y: geo.size.height * 0.38))
                }
                .stroke(DS.Color.onPlum(0.16), style: .init(lineWidth: 1, dash: [4, 5]))

                CurveBuilder.area(values, in: geo.size, scale: scale)
                    .fill(.linearGradient(colors: [tint.opacity(0.42), tint.opacity(0)],
                                          startPoint: .top, endPoint: .bottom))
                    .opacity(drawn ? 1 : 0)

                path.trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(tint, style: .init(lineWidth: 3.4, lineCap: .round))

                // Vételek és eladások kis pöttyökkel.
                let allPoints = CurveBuilder.points(values, in: geo.size, scale: scale)
                ForEach(markers.sorted(by: { $0.key < $1.key }), id: \.key) { index, kind in
                    if index < allPoints.count {
                        Circle()
                            .fill(kind == .buy ? DS.Color.positiveGreen : DS.Color.negativeCream)
                            .frame(width: 6, height: 6)
                            .position(allPoints[index])
                            .opacity(drawn ? 0.9 : 0)
                    }
                }

                if let last = allPoints.last {
                    PulsingDot(color: tint)
                        .position(last)
                        .opacity(drawn ? 1 : 0)
                }

                if let valueTag, scrub == nil {
                    Text(valueTag)
                        .font(DS.font(12.5, .medium))
                        .foregroundStyle(DS.Color.onShell())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(tint, in: .rect(cornerRadius: 13))
                        .offset(x: geo.size.width * 0.54, y: 0)
                        .opacity(drawn ? 1 : 0)
                }

                if let scrub, let index = ScrubMath.nearestIndex(to: scrub, xs: nil,
                                                                 count: points.count),
                   index < points.count {
                    ScrubBand(
                        fraction: Double(index) / Double(max(points.count - 1, 1)),
                        // A NYERS pont megy ki, nem a simított — lásd a
                        // `ScrubBand` magyarázatát.
                        reading: ScrubReading(
                            date: index < dates.count ? dates[index] : nil,
                            rows: [.init(id: "v", label: "", colorHex: 0,
                                         text: format(points[index]))]),
                        width: geo.size.width, height: geo.size.height, tint: tint)
                }
            }
            .contentShape(.rect)
            .scrubbable(width: geo.size.width, fraction: $scrub)
            .onAppear {
                withAnimation(.timingCurve(0.33, 0, 0.15, 1, duration: 2.3).delay(0.35)) {
                    drawn = true
                }
            }
        }
    }
}

/// Több platform egy tengelyen, 100-ra indexálva — a 3b ábrája.
struct IndexedChart: View {
    struct Series: Identifiable {
        let id: String
        let values: [Double]
        let color: Color
        /// Vízszintes helyek 0…1 között — a NAPOK szerint, nem sorszám
        /// szerint. Enélkül a különböző hosszúságú sorozatok egymás fölé
        /// csúsznának időben helytelenül.
        var xs: [Double]? = nil
        /// Rövid név a dátumsáv kiolvasásához (a platform monogramja).
        var label: String = ""
    }
    let series: [Series]
    /// A vezetővonal színe — a sötét héjon és a világos vásznon más kell.
    var guideColor: Color = DS.Color.onPlum(0.16)
    /// A közös időtengely két vége. Ebből számoljuk a sáv alatti dátumot.
    var axisStart: Date?
    var axisEnd: Date?
    var format: (Double) -> String = { Fmt.huf(Decimal($0)) }
    /// Kikényszerített függőleges skála. `nil` esetén az automatika dönt.
    /// Azért kell, mert a logaritmikus skálán a vonalak MAGASSÁGA nem
    /// arányos a forintokkal — ez tudatos torzítás, de csak akkor
    /// elfogadható, ha ki lehet kapcsolni.
    var forcedScale: CurveBuilder.Scale? = nil
    /// KÍVÜLRŐL vezérelt sáv-állapot. Azért kell, hogy a grafikonon KÍVÜLRE
    /// koppintva is el lehessen tüntetni: az ottani koppintás soha nem jut
    /// el ide, tehát a befogadó nézetnek kell tudnia törölni.
    var externalScrub: Binding<Double?>? = nil

    @State private var localScrub: Double?
    private var scrub: Binding<Double?> { externalScrub ?? $localScrub }

    var body: some View {
        GeometryReader { geo in
            // Közös skála: csak így összehasonlíthatók a görbék.
            let all = series.flatMap(\.values)
            let low = all.min() ?? 0, high = all.max() ?? 1
            let scale = forcedScale ?? CurveBuilder.suggestedScale(all)
            // Egyetlen aszinkron rajzfelület: a korábbi, platformonként
            // késleltetett Path-animációk 2–4 másodpercig külön rétegeket
            // kompozitáltak. Ettől a görbe darabonként töltött be, és közben
            // a fő ScrollView is elveszíthetett egy képkockát. A Canvas a
            // teljes statikus grafikont egyszerre adja át a renderelőnek.
            ZStack {
                Canvas(opaque: false, colorMode: .nonLinear,
                       rendersAsynchronously: true) { context, size in
                    for ratio in [0.34, 0.68] {
                        var guide = Path()
                        guide.move(to: .init(x: 0, y: size.height * ratio))
                        guide.addLine(to: .init(x: size.width, y: size.height * ratio))
                        context.stroke(
                            guide,
                            with: .color(guideColor),
                            style: .init(lineWidth: 1, dash: [4, 5])
                        )
                    }

                    for (index, item) in series.enumerated() {
                        let smoothed = CurveBuilder.smoothed(
                            item.values,
                            window: CurveBuilder.suggestedWindow(item.values.count)
                        )
                        let path = CurveBuilder.path(
                            smoothed, xs: item.xs, in: size,
                            low: low, high: high, scale: scale
                        )
                        context.stroke(
                            path,
                            with: .color(item.color),
                            style: .init(lineWidth: index == 0 ? 3 : 2.6,
                                         lineCap: .round)
                        )

                        guard let last = CurveBuilder.points(
                            smoothed, xs: item.xs, in: size,
                            low: low, high: high, scale: scale
                        ).last else { continue }
                        let dotSize: CGFloat = 9
                        let haloSize = dotSize * 1.85
                        context.fill(
                            Path(ellipseIn: CGRect(x: last.x - haloSize / 2,
                                                  y: last.y - haloSize / 2,
                                                  width: haloSize, height: haloSize)),
                            with: .color(item.color.opacity(0.18))
                        )
                        let dotRect = CGRect(x: last.x - dotSize / 2,
                                             y: last.y - dotSize / 2,
                                             width: dotSize, height: dotSize)
                        context.fill(Path(ellipseIn: dotRect),
                                     with: .color(DS.Color.onShell()))
                        context.stroke(Path(ellipseIn: dotRect),
                                       with: .color(item.color),
                                       lineWidth: dotSize * 0.25)
                    }
                }

                if let value = scrub.wrappedValue {
                    ScrubBand(fraction: value, reading: reading(at: value),
                              width: geo.size.width, height: geo.size.height,
                              tint: guideColor.opacity(1))
                }
            }
            .contentShape(.rect)
            .scrubbable(width: geo.size.width, fraction: scrub)
        }
    }
}

/// Görbe-geometria.
extension IndexedChart {
    /// Mi volt az adott napon — minden vonalra egy sor.
    ///
    /// Sorozatonként külön keressük a legközelebbi pontot, mert a vonalak nem
    /// ugyanazokra a napokra esnek: a megtakarításnak minden napra van
    /// egyenlege, a TBSZ-nek csak kereskedési napokra.
    func reading(at fraction: Double) -> ScrubReading {
        var date: Date?
        if let axisStart, let axisEnd, axisEnd > axisStart {
            date = axisStart.addingTimeInterval(axisEnd.timeIntervalSince(axisStart) * fraction)
        }
        let rows = series.compactMap { item -> ScrubReading.Row? in
            guard let index = ScrubMath.nearestIndex(to: fraction, xs: item.xs,
                                                     count: item.values.count),
                  index < item.values.count else { return nil }
            // A vonal SAJÁT szakaszán belül mindig írunk értéket, akkor is,
            // ha a legközelebbi mérés pár nappal odébb van: a görbe ott is
            // folytonos vonalat rajzol, tehát a kiolvasás sem hiányozhat.
            // A szakaszon KÍVÜL viszont nem találunk ki semmit.
            //
            // Korábban rögzített 6%-os távolság volt a feltétel, és emiatt a
            // ritkábban mért TBSZ értéke hol megjelent, hol nem.
            if let xs = item.xs, xs.count == item.values.count,
               let low = xs.first, let high = xs.last,
               fraction < low - 0.02 || fraction > high + 0.02 { return nil }
            return ScrubReading.Row(id: item.id, label: item.label,
                                    colorHex: item.color.hexValue,
                                    text: format(item.values[index]))
        }
        return ScrubReading(date: date, rows: rows)
    }
}

extension Color {
    /// Visszafejtett hex — a kiolvasás sora `Equatable` akar lenni, a `Color`
    /// viszont nem hasonlítható megbízhatóan.
    var hexValue: UInt32 {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(max(0, min(1, r)) * 255) << 16)
             | (UInt32(max(0, min(1, g)) * 255) << 8)
             |  UInt32(max(0, min(1, b)) * 255)
        #else
        return 0x888888
        #endif
    }
}

enum CurveBuilder {

    /// Függőleges skála.
    ///
    /// **Miért kell a logaritmikus:** ha az érték 2 800 Ft-ról 400 000-re ugrik,
    /// az lineáris tengelyen mindig függőleges vonal lesz — nem a rajzolás
    /// hibája, hanem a skáláé. Logaritmikuson az AZONOS ARÁNYÚ változás azonos
    /// elmozdulás, tehát a görbe végig olvasható marad.
    enum Scale { case linear, logarithmic }

    static func suggestedScale(_ values: [Double]) -> Scale {
        guard let low = values.min(), let high = values.max(), low > 0 else { return .linear }
        return high / low > 4 ? .logarithmic : .linear
    }

    private static func transform(_ value: Double, _ scale: Scale) -> Double {
        switch scale {
        case .linear:      value
        case .logarithmic: log10(max(value, 0.000_001))
        }
    }

    /// Középre igazított mozgóátlag.
    ///
    /// **Miért az ADATOT simítjuk, nem a görbét:** a befizetések egyetlen napon
    /// landolnak, tehát a sorozat lépcsős. Egy függőleges ugrást semmilyen
    /// illesztés nem tud íveltté tenni — a Catmull-Rom megpróbálta, és minden
    /// lépcsőnél fel-le kilengett. A mozgóátlag viszont valódi ívet ad: az
    /// ugrást néhány napra teríti szét.
    ///
    /// Ez tudatos csere: a napi pontosságot adjuk fel az olvashatóságért.
    /// A tulajdonos kérése az volt, hogy „csak viszonyítás kell". A pontos
    /// mai értéket a felső címke mutatja, azt nem a görbéről kell leolvasni.
    static func smoothed(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > window else { return values }
        let half = window / 2
        return values.indices.map { index in
            let lower = max(0, index - half)
            let upper = min(values.count - 1, index + half)
            let slice = values[lower...upper]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// A sorozat hosszához igazított ablak: rövid szakaszon ne mossa el a
    /// mozgást, hosszún viszont legyen mit simítani.
    static func suggestedWindow(_ count: Int) -> Int {
        switch count {
        case ..<20:  1          // nincs simítás
        case ..<60:  3
        case ..<150: 5
        default:     9
        }
    }

    /// `xs`: vízszintes helyek 0…1 között, pontonként. Enélkül a pontok
    /// EGYENLETESEN oszlanak el, ami csak akkor helyes, ha minden sorozat
    /// ugyanazokra a napokra esik. A kezdőképernyő közös görbéjén ez nem áll:
    /// a megtakarításnak minden napra van egyenlege, a TBSZ-nek csak
    /// kereskedési napokra, és később is kezdődik. Egyenletes elosztásnál a
    /// két vonal ugyanarra a szélességre feszül, tehát NEM egy időpont van
    /// egymás alatt — a görbe hazudna az egyidejűségről.
    static func points(_ values: [Double], xs: [Double]? = nil, in size: CGSize,
                       low: Double? = nil, high: Double? = nil,
                       scale: Scale = .linear) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let mapped = values.map { transform($0, scale) }
        let lo = transform(low ?? values.min() ?? 0, scale)
        let hi = transform(high ?? values.max() ?? 1, scale)
        let span = hi - lo
        let pad = size.height * 0.12
        let fractions = (xs?.count == values.count) ? xs : nil
        return mapped.indices.map { index in
            let fraction = fractions?[index] ?? Double(index) / Double(mapped.count - 1)
            let x = size.width * fraction
            // Vízszintes vonal, ha minden érték egyforma — nullával osztás helyett.
            let ratio = span > 0 ? (mapped[index] - lo) / span : 0.5
            let y = size.height - pad - ratio * (size.height - pad * 2)
            return CGPoint(x: x, y: y)
        }
    }

    /// Monoton köbös illesztés (Fritsch–Carlson).
    ///
    /// Garantáltan nem lő túl: sosem rajzol olyan értéket, ami nem volt.
    /// A simítás a `smoothed(_:window:)` dolga, nem ezé — a kettő együtt ad
    /// ívelt, mégis hiteles görbét.
    static func path(_ values: [Double], xs: [Double]? = nil, in size: CGSize,
                     low: Double? = nil, high: Double? = nil,
                     scale: Scale = .linear) -> Path {
        let pts = points(values, xs: xs, in: size, low: low, high: high, scale: scale)
        var path = Path()
        guard let first = pts.first else { return path }
        guard pts.count > 2 else {
            path.move(to: first)
            pts.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }

        let n = pts.count
        var deltas = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = pts[i + 1].x - pts[i].x
            deltas[i] = dx == 0 ? 0 : (pts[i + 1].y - pts[i].y) / dx
        }

        var slopes = [Double](repeating: 0, count: n)
        slopes[0] = deltas[0]
        slopes[n - 1] = deltas[n - 2]
        for i in 1..<(n - 1) {
            slopes[i] = deltas[i - 1] * deltas[i] <= 0 ? 0 : (deltas[i - 1] + deltas[i]) / 2
        }
        for i in 0..<(n - 1) where deltas[i] != 0 {
            let a = slopes[i] / deltas[i]
            let b = slopes[i + 1] / deltas[i]
            let h = a * a + b * b
            if h > 9 {
                let t = 3 / h.squareRoot()
                slopes[i] = t * a * deltas[i]
                slopes[i + 1] = t * b * deltas[i]
            }
        }

        path.move(to: first)
        for i in 0..<(n - 1) {
            let p0 = pts[i], p1 = pts[i + 1]
            let dx = (p1.x - p0.x) / 3
            path.addCurve(
                to: p1,
                control1: CGPoint(x: p0.x + dx, y: p0.y + dx * slopes[i]),
                control2: CGPoint(x: p1.x - dx, y: p1.y - dx * slopes[i + 1])
            )
        }
        return path
    }

    static func area(_ values: [Double], in size: CGSize,
                     scale: Scale = .linear) -> Path {
        var path = self.path(values, in: size, scale: scale)
        let pts = points(values, in: size, scale: scale)
        guard let first = pts.first, let last = pts.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}
