import SwiftUI

/// Import- és értékelési ellenőrző központ. A célja nem egy második
/// portfólióképernyő, hanem hogy az eltérések okát meg lehessen találni.
struct ReconciliationView: View {
    @Environment(PortfolioStore.self) private var store

    private var report: ReconciliationReport { store.reconciliationReport }

    var body: some View {
        List {
            Section {
                overview
            } header: {
                Text("Összegzés")
            }

            if !report.issues.isEmpty {
                Section {
                    ForEach(report.issues) { issue in
                        issueRow(issue)
                    }
                } header: {
                    Text("Ellenőrizendő tételek")
                }
            }

            Section {
                ForEach(report.rows) { row in
                    platformRow(row)
                }
            } header: {
                Text("Források és platformok")
            }

            if !store.treasuryPositions.isEmpty {
                Section {
                    ForEach(store.treasuryPositions) { position in
                        treasuryRow(position)
                    }
                } header: {
                    Text("Állampapír-sorok")
                }
            }

            if !store.cryptoPositions.isEmpty {
                Section {
                    ForEach(store.cryptoPositions) { position in
                        cryptoRow(position)
                    }
                } header: {
                    Text("Kripto-pozíciók · csak olvasható export")
                }
            }

            Section {
                Text("Az ellenőrző központ a helyi importokat, az árfolyamforrást és az egyenlegek frissességét hasonlítja össze. A piaci érték szolgáltatónként és időpont szerint eltérhet; az eltérés önmagában nem import-hiba.")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.56))
            } header: {
                Text("Fontos")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .navigationTitle("Adat-ellenőrzés")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: severityIcon(report.severity))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(severityColor(report.severity))
                    .frame(width: 36, height: 36)
                    .background(severityColor(report.severity).opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(report.isClear ? "Nincs eltérés" : "Ellenőrzés szükséges")
                        .font(DS.rowTitle)
                    Text(report.isClear
                         ? "A jelenlegi adatok között nem találtam ismert anomáliát."
                         : "\(report.issues.count) ellenőrizendő jelzés a számítási láncban.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.56))
                }
            }

            HStack(spacing: 18) {
                metric("Nettó vagyon", Fmt.huf(store.grandTotalHUF))
                metric("Befektethető", Fmt.huf(store.investableHUF))
            }
            Text("Frissítve: \(Fmt.day(report.generatedAt)) · \(Fmt.time(report.generatedAt))")
                .font(DS.font(10.5, .regular).monospacedDigit())
                .foregroundStyle(DS.Color.inkSoft(0.44))
        }
        .padding(.vertical, 4)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.font(10.5, .regular))
                .foregroundStyle(DS.Color.inkSoft(0.52))
            Text(value)
                .font(DS.font(15, .semibold).monospacedDigit())
        }
    }

    private func issueRow(_ issue: ReconciliationIssue) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: severityIcon(issue.severity))
                .foregroundStyle(severityColor(issue.severity))
                .frame(width: 28, height: 28)
                .background(severityColor(issue.severity).opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title).font(DS.rowTitle)
                Text(issue.detail)
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func platformRow(_ row: ReconciliationRow) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: severityIcon(row.severity))
                .foregroundStyle(severityColor(row.severity))
                .frame(width: 28, height: 28)
                .background(severityColor(row.severity).opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.platformName).font(DS.rowTitle)
                    Spacer(minLength: 8)
                    Text(Fmt.huf(row.valueHUF))
                        .font(DS.font(13.5, .semibold).monospacedDigit())
                }
                Text(row.source)
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.52))
                if let change = row.changeHUF {
                    Text("Befizetésekhez képest \(change >= 0 ? "+" : "")\(Fmt.huf(change))")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.sign(change.doubleValue))
                }
                Text(row.detail)
                    .font(DS.font(10.5, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func treasuryRow(_ position: StateTreasuryPosition) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(position.name)
                    .font(DS.rowTitle)
                Spacer(minLength: 8)
                Text(Fmt.huf(position.currentValueHUF))
                    .font(DS.font(13.5, .semibold).monospacedDigit())
            }
            HStack(spacing: 8) {
                if let isin = position.isin {
                    Text(isin).font(DS.meta.monospacedDigit())
                }
                if let invested = position.investedValueHUF {
                    Text("Bekerülés \(Fmt.huf(invested))").font(DS.meta)
                }
                if let maturity = position.maturityDate {
                    Text("Lejárat \(Fmt.day(maturity))").font(DS.meta)
                }
            }
            .foregroundStyle(DS.Color.inkSoft(0.52))
        }
        .padding(.vertical, 2)
    }

    private func cryptoRow(_ position: CryptoPosition) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(position.name).font(DS.rowTitle)
                Spacer(minLength: 8)
                Text(Fmt.huf(position.currentValueHUF))
                    .font(DS.font(13.5, .semibold).monospacedDigit())
            }
            HStack(spacing: 8) {
                Text(position.symbol).font(DS.meta.monospacedDigit())
                if let quantity = position.quantity {
                    Text("\(Fmt.decimal(quantity, max: 8)) db").font(DS.meta)
                }
                if let asOf = position.asOf {
                    Text("export: \(Fmt.day(asOf))").font(DS.meta)
                }
            }
            .foregroundStyle(DS.Color.inkSoft(0.52))
            Text(position.source)
                .font(DS.font(10.5, .regular))
                .foregroundStyle(DS.Color.inkSoft(0.42))
        }
        .padding(.vertical, 2)
    }

    private func severityIcon(_ severity: ReconciliationSeverity) -> String {
        switch severity {
        case .clear: return "checkmark.circle.fill"
        case .notice: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private func severityColor(_ severity: ReconciliationSeverity) -> Color {
        switch severity {
        case .clear: return DS.Color.positiveGreen
        case .notice: return DS.Color.iconFX
        case .warning: return DS.Color.iconTime
        case .critical: return DS.Color.negativeCream
        }
    }
}
