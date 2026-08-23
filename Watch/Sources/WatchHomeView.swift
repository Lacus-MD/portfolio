import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    total
                    if !model.summary.spark.isEmpty {
                        WatchSpark(values: model.summary.spark, tint: tint)
                            .frame(height: 34)
                    }
                    if !model.summary.periods.isEmpty { periodRow }
                    ForEach(model.summary.rows) { row in
                        platformRow(row)
                    }
                    if model.summary.rows.isEmpty { empty }
                    footer
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Portfólió")
        }
    }

    private var tint: Color {
        model.summary.gainPct < 0 ? DS.Color.negativeCream : DS.Color.positiveGreen
    }

    private var total: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.compact(model.summary.totalHUF, currency: "HUF"))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: model.summary.gainPct >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text(Fmt.percent(model.summary.gainPct))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(tint)
        }
    }

    /// Napi / heti / havi eredmény. Az órán a százalék a fontos — a forint
    /// összeg nem férne ki olvashatóan, azt a telefon mutatja.
    private var periodRow: some View {
        HStack(spacing: 6) {
            ForEach(model.summary.periods) { period in
                VStack(spacing: 1) {
                    Text(period.title)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(Fmt.percent(period.pct, digits: 1))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(period.pct < 0 ? DS.Color.negativeCream : DS.Color.positiveGreen)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 7))
            }
        }
        .padding(.top, 2)
    }

    private func platformRow(_ row: WatchSummary.Row) -> some View {
        HStack(spacing: 8) {
            Text(row.monogram)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(accentColor(row.accent), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(Fmt.compact(row.valueHUF, currency: "HUF"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(Fmt.percent(row.gainPct, digits: 1))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(row.gainPct < 0 ? DS.Color.negativeCream : DS.Color.positiveGreen)
        }
        .padding(.vertical, 5)
    }

    private func accentColor(_ raw: String) -> Color {
        switch raw {
        case "mint":  DS.Color.mint
        case "lilac": DS.Color.lilac
        default:      DS.Color.coral
        }
    }

    private var empty: some View {
        Text("Nyisd meg a telefonos appot, hogy átküldje az adatot.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }

    @ViewBuilder private var footer: some View {
        if let age = model.age {
            HStack(spacing: 4) {
                if model.isStale {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 9))
                }
                Text("Mérve \(age)")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }
}
