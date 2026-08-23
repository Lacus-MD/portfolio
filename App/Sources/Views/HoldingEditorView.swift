import SwiftUI

struct HoldingEditorView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let existing: Holding?

    @State private var isin: String
    @State private var ticker: String
    @State private var name: String
    @State private var quantity: String
    @State private var averageCost: String
    @State private var tbszYear: Int

    init(holding: Holding?) {
        self.existing = holding
        _isin = State(initialValue: holding?.isin ?? "")
        _ticker = State(initialValue: holding?.ticker ?? "")
        _name = State(initialValue: holding?.name ?? "")
        _quantity = State(initialValue: holding.map { Fmt.decimal($0.quantity) } ?? "")
        _averageCost = State(initialValue: holding.map { Fmt.decimal($0.averageCost) } ?? "")
        _tbszYear = State(initialValue: holding?.tbszYear ?? Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A katalógus a hét ellenőrzött Vanguard ETF-et kínálja, de az
                    // ISIN kézzel is felülírható — más alapot is lehet követni.
                    Menu {
                        ForEach(Holding.catalog, id: \.isin) { entry in
                            Button(entry.ticker + " — " + entry.name) {
                                isin = entry.isin
                                ticker = entry.ticker
                                name = entry.name
                            }
                        }
                    } label: {
                        HStack {
                            Text("Alap kiválasztása")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Vagy írd be kézzel bármelyik ETF ISIN-jét — az árfolyam ISIN alapján jön a Xetráról.")
                }

                Section("Azonosítás") {
                    LabeledContent("ISIN") {
                        TextField("IE00BK5BQT80", text: $isin)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Ticker") {
                        TextField("VWCE", text: $ticker)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Név") {
                        TextField("Alap neve", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Pozíció") {
                    LabeledContent("Darabszám") {
                        TextField("128,4", text: $quantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Átlagár (EUR)") {
                        TextField("118,20", text: $averageCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("TBSZ gyűjtőév", selection: $tbszYear) {
                        ForEach(yearRange, id: \.self) { Text(String($0)).tag($0) }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Pozíció törlése", role: .destructive) {
                            if let index = store.holdings.firstIndex(where: { $0.id == existing?.id }) {
                                store.delete(at: IndexSet(integer: index))
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Új pozíció" : "Pozíció")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") { commit() }.disabled(!isValid)
                }
            }
        }
        .tint(DS.Color.coral)
    }

    private var yearRange: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 10)...current).reversed()
    }

    private var parsedQuantity: Decimal? { Self.parse(quantity) }
    private var parsedCost: Decimal? { Self.parse(averageCost) }

    private var isValid: Bool {
        !isin.trimmingCharacters(in: .whitespaces).isEmpty
            && !ticker.trimmingCharacters(in: .whitespaces).isEmpty
            && (parsedQuantity ?? 0) > 0
            && (parsedCost ?? 0) > 0
    }

    private func commit() {
        guard let quantity = parsedQuantity, let cost = parsedCost else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespaces).uppercased()

        var holding = existing ?? Holding(
            isin: "", ticker: "", name: "", quantity: 0, averageCost: 0, tbszYear: tbszYear
        )
        holding.isin = isin.trimmingCharacters(in: .whitespaces).uppercased()
        holding.ticker = trimmedTicker
        holding.name = trimmedName.isEmpty ? trimmedTicker : trimmedName
        holding.quantity = quantity
        holding.averageCost = cost
        holding.tbszYear = tbszYear

        if existing == nil { store.add(holding) } else { store.update(holding) }
        Task { await store.refresh() }
        dismiss()
    }

    /// Vesszőt és pontot is elfogad tizedesjelként — magyar billentyűn vessző jön.
    private static func parse(_ text: String) -> Decimal? {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
