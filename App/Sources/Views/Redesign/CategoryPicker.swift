import SwiftUI

/// Egy tétel átsorolása kézzel.
///
/// A kézi döntés ERŐSEBB a szabálynál: az újraimport nem írja felül. Enélkül
/// a következő kivonat-beolvasás visszatenné oda, ahonnan elmozdítottad —
/// és a javítás értelmetlen lenne.
struct CategoryPicker: View {
    let entry: ExpenseEntry
    let onPick: (ExpenseCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.merchant).font(DS.font(16, .semibold))
                        Text("\(Fmt.day(entry.date)) · \(Fmt.huf(entry.magnitude))")
                            .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.5))
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    ForEach(ExpenseCategory.allCases) { category in
                        Button { onPick(category) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Color.coral)
                                    .frame(width: 24)
                                Text(category.label).font(DS.rowTitle)
                                Spacer()
                                if category == entry.category {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DS.Color.coral)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Kategória")
                } footer: {
                    Text("Amit kézzel átsorolsz, azt a következő kivonat-beolvasás nem írja felül.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.canvas)
            .foregroundStyle(DS.Color.ink)
            .navigationTitle("Átsorolás")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
            }
        }
        .tint(DS.Color.coral)
    }
}
