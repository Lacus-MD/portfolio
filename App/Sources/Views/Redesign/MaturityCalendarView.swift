import SwiftUI

/// Kamat- és lejárati események naptára.
struct MaturityCalendarView: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        List {
            if store.maturityCalendarEvents.isEmpty {
                Section {
                    Text("Nincs jelenleg naptáradathoz kapcsolódó esemény.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.55))
                } header: {
                    Text("Események")
                }
            } else {
                ForEach(groupedEvents.keys.sorted(), id: \.self) { key in
                    if let kind = MaturityCalendarEvent.Kind(rawValue: key),
                       let events = groupedEvents[key] {
                        Section {
                            ForEach(events) { event in
                                eventRow(event)
                            }
                        } header: {
                            Text(kindTitle(kind))
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A gyűjtőév vége a következő TBSZ-befizetések utolsó napját mutatja.")
                        .font(DS.rowTitle)
                    Text("A 3/5 éves eseményeknél a lejárat a gyűjtőévhez képest 3, illetve 5 év.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.55))
                    Text("A megtakarítási sor az aktuális becslés alapján, a legutóbbi kivonat és kamat alapon becsült eseményt tartalmazza.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.55))
                }
            } header: {
                Text("Megjegyzés")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .navigationTitle("Kamat- és lejárati naptár")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var groupedEvents: [String: [MaturityCalendarEvent]] {
        Dictionary(grouping: store.maturityCalendarEvents) { $0.kind.rawValue }
            .mapValues { events in events.sorted { $0.date < $1.date } }
    }

    @ViewBuilder private func eventRow(_ event: MaturityCalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kindIcon(event.kind))
                .foregroundStyle(kindColor(event.kind))
                .frame(width: 28, height: 28)
                .background(kindColor(event.kind).opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(event.title)
                        .font(DS.rowTitle)
                    Spacer()
                    Text(Fmt.day(event.date))
                        .font(DS.font(11.5, .medium).monospacedDigit())
                        .foregroundStyle(DS.Color.inkSoft(0.5))
                }

                Text(event.subtitle)
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.5))

                if let platformID = event.platformID,
                   let summary = store.platformSummaries.first(where: { $0.platform.id == platformID }) {
                    Text(summary.platform.name)
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.43))
                }

                if event.daysFromToday != 0 {
                    let relativeDays = event.daysFromToday
                    Text(relativeDays > 0 ? "\(relativeDays) nap hátra" : "\(-relativeDays) napja")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.45))
                }
            }

            kindTag(event.kind)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func kindTag(_ kind: MaturityCalendarEvent.Kind) -> some View {
        Text(kindLabel(kind))
            .font(DS.font(10, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(kindColor(kind), in: Capsule())
    }

    private func kindTitle(_ kind: MaturityCalendarEvent.Kind) -> String {
        switch kind {
        case .collectionDeadline: return "Gyűjtőév vége"
        case .threeYear: return "3 éves forduló"
        case .fiveYear: return "5 éves adómentes lejárat"
        case .savingsRate: return "Megtakarítási frissítés"
        }
    }

    private func kindLabel(_ kind: MaturityCalendarEvent.Kind) -> String {
        switch kind {
        case .collectionDeadline: return "GYŰJTŐÉV"
        case .threeYear: return "3 ÉV"
        case .fiveYear: return "5 ÉV"
        case .savingsRate: return "KAMAT"
        }
    }

    private func kindIcon(_ kind: MaturityCalendarEvent.Kind) -> String {
        switch kind {
        case .collectionDeadline: return "calendar.badge.clock"
        case .threeYear: return "clock.badge.checkmark"
        case .fiveYear: return "checkmark.seal"
        case .savingsRate: return "percent"
        }
    }

    private func kindColor(_ kind: MaturityCalendarEvent.Kind) -> Color {
        switch kind {
        case .collectionDeadline: return DS.Color.iconTime
        case .threeYear: return DS.Color.positiveGreen
        case .fiveYear: return DS.Color.coral
        case .savingsRate: return DS.Color.iconFX
        }
    }
}
