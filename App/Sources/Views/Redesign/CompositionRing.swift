import SwiftUI

/// Az alap összetétele gyűrűs diagramon.
///
/// A „többi" szelet szándékosan uralja az ábrát: a top-10 a teljes alapnak
/// csak a **22,7%-a**, 3 757 papírból. Ha csak a tízet rajzolnánk ki, az azt
/// sugallná, hogy ezek teszik ki a portfóliót — pedig a mozgás négyötödét a
/// többi hozza.
struct CompositionRing: View {
    let composition: FundComposition
    let tint: Color

    private var slices: [(name: String, pct: Double, color: Color)] {
        let palette: [Color] = [
            DS.Color.coral, DS.Color.lilac, DS.Color.mint,
            DS.Color.coral.opacity(0.75), DS.Color.lilac.opacity(0.75),
            DS.Color.mint.opacity(0.75), DS.Color.coral.opacity(0.55),
            DS.Color.lilac.opacity(0.55), DS.Color.mint.opacity(0.55),
            DS.Color.coral.opacity(0.4),
        ]
        var result = composition.top.enumerated().map {
            ($1.name, $1.weightPct, palette[$0 % palette.count])
        }
        result.append(("Többi \(Fmt.count(composition.totalHoldings - composition.top.count)) papír",
                       composition.restPct, DS.Color.onShell(0.16)))
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mi van az alapban").font(DS.section)
                Spacer()
                Text("\(composition.asOf) · \(Fmt.count(composition.totalHoldings)) papír")
                    .font(DS.font(11, .regular))
                    .foregroundStyle(DS.Color.onPlum(0.45))
            }

            HStack(alignment: .center, spacing: 18) {
                ring.frame(width: 116, height: 116)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(slices.prefix(5).enumerated()), id: \.offset) { _, slice in
                        legendRow(slice)
                    }
                    Text("+ további \(composition.top.count - 5) a top-10-ből")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.onPlum(0.45))
                }
                Spacer(minLength: 0)
            }

            Text("A top-10 az alap \(Fmt.percentPlain(100 - composition.restPct))-a. A többit \(Fmt.count(composition.totalHoldings - composition.top.count)) másik papír adja — a mozgás nagyobb részét ők hozzák, nem ez a tíz.")
                .font(DS.meta)
                .foregroundStyle(DS.Color.onPlum(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ring: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            var start = Angle.degrees(-90)
            for slice in slices {
                let sweep = Angle.degrees(slice.pct / 100 * 360)
                var path = Path()
                path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                            radius: rect.width / 2,
                            startAngle: start, endAngle: start + sweep,
                            clockwise: false)
                context.stroke(path, with: .color(slice.color),
                               style: StrokeStyle(lineWidth: 15))
                start = start + sweep
            }
        }
    }

    private func legendRow(_ slice: (name: String, pct: Double, color: Color)) -> some View {
        HStack(spacing: 7) {
            Circle().fill(slice.color).frame(width: 8, height: 8)
            Text(slice.name).font(DS.meta)
            Spacer(minLength: 4)
            Text(String(format: "%.1f%%", slice.pct))
                .font(DS.meta.monospacedDigit())
                .foregroundStyle(DS.Color.onPlum(0.6))
        }
    }
}
