import SwiftUI

/// Adatfrissességi központ: egy helyen láthatók a státuszok.
struct DataFreshnessCenterView: View {
    @Environment(PortfolioStore.self) private var store

    private var groupedItems: [String: [DataFreshnessItem]] {
        Dictionary(grouping: store.dataFreshnessItems) { $0.category }
            .mapValues { rows in rows.sorted { $0.state.rawValue < $1.state.rawValue } }
    }

    var body: some View {
        List {
            if store.dataFreshnessItems.isEmpty {
                Section {
                    Text("Még nem volt elegendő adatfrissítés a kiértékeléshez.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.55))
                } header: {
                    Text("Adatállapot")
                }
            } else {
                ForEach(groupedItems.keys.sorted(), id: \.self) { category in
                    if let rows = groupedItems[category] {
                        Section {
                            ForEach(rows) { row in
                                freshnessRow(row)
                            }
                        } header: {
                            Text(category)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .navigationTitle("Adatfrissesség")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    @ViewBuilder private func freshnessRow(_ row: DataFreshnessItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stateIcon(row.state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(stateColor(row.state))
                .frame(width: 32, height: 32)
                .background(stateColor(row.state).opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.title)
                        .font(DS.rowTitle)
                    Spacer(minLength: 0)
                    Text(stateLabel(row.state))
                        .font(DS.font(11.5, .medium).monospacedDigit())
                        .foregroundStyle(stateColor(row.state))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(stateColor(row.state).opacity(0.16), in: Capsule())
                }
                Text(row.detail)
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.56))
                    .fixedSize(horizontal: false, vertical: true)

                if let lastUpdated = row.lastUpdated {
                    Text("Utolsó frissítés: \(Fmt.day(lastUpdated))")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.45))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stateLabel(_ state: FreshnessState) -> String {
        switch state {
        case .fresh: return "Friss"
        case .good: return "Elfogadható"
        case .stale: return "Elavult"
        case .outOfDate: return "Régies"
        case .missing: return "Hiányzik"
        }
    }

    private func stateIcon(_ state: FreshnessState) -> String {
        switch state {
        case .fresh: return "checkmark.circle.fill"
        case .good: return "clock.arrow.circlepath"
        case .stale: return "exclamationmark.triangle.fill"
        case .outOfDate: return "xmark.octagon.fill"
        case .missing: return "questionmark.circle.fill"
        }
    }

    private func stateColor(_ state: FreshnessState) -> Color {
        switch state {
        case .fresh: return DS.Color.positiveGreen
        case .good: return DS.Color.iconTime
        case .stale: return DS.Color.inkSoft(0.7)
        case .outOfDate: return DS.Color.negativeCream
        case .missing: return DS.Color.inkSoft(0.5)
        }
    }
}

