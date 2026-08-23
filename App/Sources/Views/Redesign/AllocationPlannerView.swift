import SwiftUI

/// Befektethető vagyonra vonatkozó célallokáció és új pénz elosztási javaslat.
struct AllocationPlannerView: View {
    @Environment(PortfolioStore.self) private var store
    @State private var targets: [String: Double] = [:]
    @State private var amountText = ""
    @State private var loadedTargets = false
    @State private var notice: Notice?

    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var investable: [PlatformSummary] {
        store.investableSummaries
    }

    private var targetDraft: [String: Double] {
        var result = investable.reduce(into: [String: Double]()) { acc, summary in
            acc[summary.platform.id] = targets[summary.platform.id] ?? 0
        }

        guard !result.isEmpty else { return result }

        let normalized = store.normalizeAllocationTargets(result)
        result = normalized

        return result
    }

    private var additionalAmount: Decimal {
        guard !amountText.isEmpty else { return 0 }
        let cleaned = amountText
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private var recommendations: [AllocationSuggestion] {
        store.allocationRecommendations(for: additionalAmount)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Befektethető vagyon").font(DS.rowTitle)
                        Text("Az alábbi érték papírokat, megtakarításokat kezeljük befektetésként.")
                            .font(DS.meta)
                            .foregroundStyle(DS.Color.inkSoft(0.55))

                        Divider().overlay(DS.Color.onPlum(0.12))

                        HStack {
                            Text("Összesen").font(DS.rowTitle)
                            Spacer()
                            Text(Fmt.huf(store.investableHUF))
                                .font(DS.font(14, .semibold).monospacedDigit())
                                .foregroundStyle(DS.Color.coral)
                        }

                        if store.nonInvestableHUF > 0 {
                            HStack {
                                Text("Nem befektethető (kifizető számla, tartozás)").font(DS.meta)
                                Spacer()
                                Text(Fmt.huf(store.nonInvestableHUF))
                                    .font(DS.font(12.5, .medium).monospacedDigit())
                                    .foregroundStyle(DS.Color.inkSoft(0.6))
                            }
                        }
                    }
                }

                if !investable.isEmpty {
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Célarányok")
                            Text("Állítsd be, mennyi százalékot szeretnél tartani platformonként. A mentés azonnal frissül.")
                                .font(DS.meta)
                                .foregroundStyle(DS.Color.inkSoft(0.55))

                ForEach(investable) { summary in
                    let platformID = summary.platform.id
                    VStack(spacing: 10) {
                        HStack(alignment: .top) {
                            Circle()
                                .fill(summary.platform.accent.color)
                                .frame(width: 9, height: 9)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(summary.platform.name).font(DS.rowTitle)
                                            Text("Aktuálisan: \(Fmt.percentPlain(summary.share * 100))")
                                                .font(DS.meta)
                                                .foregroundStyle(DS.Color.inkSoft(0.55))
                                        }
                                        Spacer(minLength: 8)
                                        Text(String(format: "%.1f%%", targetDraft[platformID] ?? 0))
                                            .font(DS.font(12, .medium).monospacedDigit())
                                    }

                                    Slider(
                                        value: binding(for: platformID),
                                        in: 0...100,
                                        step: 0.5
                                    ) {
                                        Text(summary.platform.name)
                                    }
                                }

                                if platformID != investable.last?.platform.id {
                                    Rectangle()
                                        .fill(DS.Color.inkSoft(0.08))
                                        .frame(height: 0.8)
                                }
                            }

                            Button {
                                let equal = investable.isEmpty
                                    ? [:]
                                    : Dictionary(uniqueKeysWithValues: investable.map {
                                        ($0.platform.id, 100.0 / Double(investable.count))
                                    })
                                targets = equal
                                persistTargets()
                                notice = Notice(title: "Kész", message: "A célarányokat egyenlően visszaállítottuk.")
                            } label: {
                                Text("Egyenletes visszaállítás")
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(DS.Color.card.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .font(DS.font(13, .medium))
                            .foregroundStyle(DS.Color.ink)
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Új pénz elosztása")

                            TextField("0", text: $amountText)
                                .keyboardType(.decimalPad)
                                .font(DS.font(17, .medium))
                                .padding(12)
                                .background(DS.Color.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.Color.inkSoft(0.1)))

                            if recommendations.isEmpty {
                                if additionalAmount <= 0 {
                                    Text("Írj be egy pozitív összeget, hogy lásd a javaslatot a következő befizetésre.")
                                        .font(DS.meta)
                                        .foregroundStyle(DS.Color.inkSoft(0.55))
                                } else {
                                    Text("A jelenlegi célok alapján még nincs platform a megjelenítéshez.")
                                        .font(DS.meta)
                                        .foregroundStyle(DS.Color.inkSoft(0.55))
                                }
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(recommendations) { item in
                                        recommendationRow(item)
                                    }
                                }

                                Text("A " + Fmt.huf(additionalAmount) + " összeget a célarányok felé javasoltuk elosztani.")
                                    .font(DS.meta)
                                    .foregroundStyle(DS.Color.inkSoft(0.55))
                            }
                        }
                    }
                } else {
                    card {
                        VStack(spacing: 12) {
                            Text("Még nincs befektethető platform").font(DS.rowTitle)
                            Text("A célallokáció csak értékpapír- és megtakarítási számláknál működik. Előbb importáld be a portfóliódat.")
                                .font(DS.meta)
                                .foregroundStyle(DS.Color.inkSoft(0.55))
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, DS.bottomPadding)
            .readableWidth()
        }
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .navigationTitle("Célallokáció")
        .toolbarBackground(DS.Color.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .tint(DS.Color.coral)
        .onAppear(perform: resetFromStore)
        .onChange(of: targets) { _ in
            guard loadedTargets else { return }
            persistTargets()
        }
        .alert(item: $notice) { item in
            Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
        }
    }

    private func resetFromStore() {
        targets = store.allocationTargetsForEditing()
        amountText = amountText.isEmpty ? "" : amountText
        loadedTargets = true
    }

    private func binding(for id: String) -> Binding<Double> {
        Binding {
            targetDraft[id] ?? 0
        } set: { newValue in
            targets[id] = newValue
        }
    }

    private func persistTargets() {
        let normalized = store.normalizeAllocationTargets(targets)
        targets = normalized
        store.setAllocationTargets(normalized)
    }

    @ViewBuilder private func sectionHeader(_ title: String) -> some View {
        Text(title).font(DS.rowTitle)
    }

    @ViewBuilder private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(DS.Color.card)
            .overlay(RoundedRectangle(cornerRadius: DS.R.platformCard).stroke(DS.Color.inkSoft(0.08), lineWidth: 0.75))
            .clipShape(RoundedRectangle(cornerRadius: DS.R.platformCard, style: .continuous))
    }

    @ViewBuilder private func recommendationRow(_ item: AllocationSuggestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.coral)
                .frame(width: 32, height: 32)
                .background(DS.Color.coral.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.platformName).font(DS.rowTitle)
                Text("Cél: \(Fmt.percentPlain(item.targetPercent))")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.55))
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.huf(item.recommendAmount))
                    .font(DS.font(13, .medium).monospacedDigit())
                    .foregroundStyle(DS.Color.coral)
                Text("javaslat")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.45))
            }
        }
        .padding(.vertical, 4)
    }
}
