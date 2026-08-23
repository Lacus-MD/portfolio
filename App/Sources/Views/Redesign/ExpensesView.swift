import SwiftUI

/// Kiadások fül — mire ment el a pénz, a kivonatokból.
///
/// **Nem minden kimenő forint kiadás.** A Lightyearbe vagy a Revolutba
/// átvezetett pénz a saját számládra megy, az állampapír-vásárlás szintén —
/// ezek külön állnak, és nem számítanak bele a „költés" összegbe. Beszámítva
/// ugyanaz a forint kétszer szerepelne: egyszer költésként, egyszer
/// vagyonként a Portfólió fülön.
struct ExpensesView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var month: Date = Calendar.current.startOfMonth(for: Date())
    @State private var expanded: ExpenseCategory?
    @State private var recategorizing: ExpenseEntry?
    @State private var showRecurring = false

    private var calendar: Calendar { Calendar.current }

    /// Azok a hónapok, amikről van adat — csak ezek közt lehet lépkedni.
    private var months: [Date] {
        Set(store.expenses.map { calendar.startOfMonth(for: $0.date) })
            .sorted(by: >)
    }

    private var entries: [ExpenseEntry] {
        store.expenses.filter {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month) && $0.isExpense
        }
    }

    private var byCategory: [(category: ExpenseCategory, total: Decimal, items: [ExpenseEntry])] {
        Dictionary(grouping: entries, by: \.category)
            .map { (category: $0.key,
                    total: $0.value.reduce(Decimal(0)) { $0 + $1.magnitude },
                    items: $0.value.sorted { $0.magnitude > $1.magnitude }) }
            .sorted { $0.total > $1.total }
    }

    private var spending: Decimal {
        byCategory.filter(\.category.isSpending).reduce(Decimal(0)) { $0 + $1.total }
    }
    private var moved: Decimal {
        byCategory.filter { !$0.category.isSpending }.reduce(Decimal(0)) { $0 + $1.total }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 22) {
                        if entries.isEmpty {
                            emptyState
                        } else {
                            importReminder
                            cardDue
                            summary
                            fixedVsVariable
                            recurringCard
                            breakdown
                            movedSection
                            footnote
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, DS.bottomPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .readableWidth(sizeClass == .regular ? 820 : 560)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("expenses-scroll-content")
                }
                .scrollIndicators(.hidden)
                // A függőleges ScrollView iOS-on oldalirányban is engedte a
                // gumihúzást, ezért a teljes kártyaoszlop elcsúszhatott a
                // képernyő széléig. Ha vízszintesen nincs túlméretes tartalom,
                // a basedOnSize teljesen letiltja ezt a bounce-ot.
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .background(DS.Color.canvas)
            .foregroundStyle(DS.Color.ink)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $recategorizing) { entry in
                CategoryPicker(entry: entry) { category in
                    store.recategorize(entry, to: category)
                    recategorizing = nil
                }
            }
        }
        .onAppear {
            if let newest = months.first, !months.contains(month) { month = newest }
        }
    }

    // MARK: - Fejléc

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("KIADÁSOK")
                .font(DS.font(10, .semibold)).tracking(1.0)
                .foregroundStyle(DS.Color.inkSoft(0.36))
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.month(month))
                    .font(DS.font(29, .semibold))
                Spacer()
                monthStepper
            }
            .padding(.top, 1)
            Rectangle().fill(DS.Color.inkSoft(0.075)).frame(height: 1)
                .padding(.top, 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, DS.topPadding)
    }

    private var monthStepper: some View {
        HStack(spacing: 4) {
            step(-1, "chevron.left")
            step(1, "chevron.right")
        }
    }

    private func step(_ direction: Int, _ icon: String) -> some View {
        // Csak olyan hónapra lépünk, amiről VAN adat: üres hónapokon
        // átlapozni azt sugallná, hogy akkor nem költöttél.
        let target = calendar.date(byAdding: .month, value: direction, to: month)
        let available = target.map { candidate in
            months.contains { calendar.isDate($0, equalTo: candidate, toGranularity: .month) }
        } ?? false
        return Button {
            if let target, available { withAnimation(.snappy(duration: 0.2)) { month = target } }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .pastelCardBackground(in: Circle())
                .overlay(Circle().stroke(DS.Color.inkSoft(0.075)))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
    }

    // MARK: - Összegzés

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EBBEN A HÓNAPBAN ELKÖLTVE")
                .font(DS.font(10, .semibold)).tracking(1.0)
                .foregroundStyle(DS.Color.inkSoft(0.36))
            Text(Fmt.huf(spending))
                .font(DS.font(33, .semibold).monospacedDigit())
                .padding(.top, 4)
            if moved > 0 {
                Text("Ezen felül \(Fmt.huf(moved)) ment a saját számláidra vagy törlesztésre — az nem költés, lent külön látod.")
                    .font(DS.font(12, .regular))
                    .foregroundStyle(DS.Color.inkSoft(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Color.inkSoft(0.075)))
    }

    // MARK: - Bontás

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("MIRE MENT EL")
            ForEach(byCategory.filter(\.category.isSpending), id: \.category) { group in
                categoryRow(group)
            }
        }
    }

    @ViewBuilder private var movedSection: some View {
        let other = byCategory.filter { !$0.category.isSpending }
        if !other.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("NEM KÖLTÉS — SAJÁT SZÁMLÁRA")
                ForEach(other, id: \.category) { categoryRow($0) }
            }
        }
    }

    private func categoryRow(_ group: (category: ExpenseCategory, total: Decimal,
                                       items: [ExpenseEntry])) -> some View {
        let open = expanded == group.category
        let share = spending > 0 && group.category.isSpending
            ? (group.total / spending).doubleValue : 0
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    expanded = open ? nil : group.category
                }
            } label: {
                VStack(spacing: 9) {
                    HStack(spacing: 12) {
                        Image(systemName: group.category.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(DS.Color.coral)
                            .frame(width: 34, height: 34)
                            .background(DS.Color.coral.opacity(0.15), in: .rect(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.category.label).font(DS.font(15, .semibold))
                            Text("\(group.items.count) tétel")
                                .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.4))
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Fmt.huf(group.total))
                                .font(DS.font(15, .semibold).monospacedDigit())
                            if share > 0 {
                                Text(Fmt.percentPlain(share * 100))
                                    .font(DS.meta.monospacedDigit())
                                    .foregroundStyle(DS.Color.inkSoft(0.4))
                            }
                        }
                    }
                    if group.category.isSpending {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.Color.inkSoft(0.10))
                                Capsule().fill(DS.Color.coral)
                                    .frame(width: max(geo.size.width * share, 2))
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if open { items(group.items) }
        }
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DS.Color.inkSoft(0.075)))
        .foregroundStyle(DS.Color.ink)
    }

    private func items(_ list: [ExpenseEntry]) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Color.inkSoft(0.075)).frame(height: 1)
            ForEach(list.prefix(25)) { entry in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.merchant)
                            .font(DS.font(13, .medium))
                            .lineLimit(1)
                        Text("\(Fmt.day(entry.date)) · \(accountName(entry.account))")
                            .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.4))
                    }
                    Spacer(minLength: 6)
                    Text(Fmt.huf(entry.magnitude))
                        .font(DS.font(13, .medium).monospacedDigit())
                    if entry.manualCategory {
                        // Jelezzük, hogy ezt TE sorolted át — az újraimport
                        // ilyenkor nem írja felül.
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Color.inkSoft(0.3))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(.rect)
                .onTapGesture { recategorizing = entry }
            }
            if list.count > 25 {
                Text("+\(list.count - 25) további tétel")
                    .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.4))
                    .padding(.bottom, 10)
            }
        }
        .transition(.opacity)
    }

    private func accountName(_ id: String) -> String {
        store.resolvedPlatforms.first { $0.id == id }?.name ?? id
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.font(10, .semibold)).tracking(1.0)
            .foregroundStyle(DS.Color.inkSoft(0.36))
    }

    // MARK: - Fix vs. változó

    private var thisMonth: SpendingAnalysis.Month? {
        SpendingAnalysis.months(store.expenses)
            .first { calendar.isDate($0.start, equalTo: month, toGranularity: .month) }
    }

    /// Mennyi megy el, mielőtt bármit döntenél.
    ///
    /// A fix rész (törlesztés, rezsi, biztosítás, előfizetés, banki díj)
    /// akkor is elmegy, ha egy hónapig ki sem lépsz a lakásból. A változó
    /// az, amiről tényleg te döntesz.
    @ViewBuilder private var fixedVsVariable: some View {
        if let month = thisMonth, month.spending > 0 {
            let fixedShare = (month.fixed / month.spending).doubleValue
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("FIX ÉS VÁLTOZÓ")
                    .padding(.bottom, 10)

                GeometryReader { geo in
                    HStack(spacing: 3) {
                        Capsule().fill(DS.Color.coral)
                            .frame(width: max(geo.size.width * fixedShare - 2, 2))
                        Capsule().fill(DS.Color.inkSoft(0.18))
                    }
                }
                .frame(height: 10)

                HStack(alignment: .top) {
                    legend("Fix", month.fixed, DS.Color.coral)
                    Spacer()
                    legend("Változó", month.variable, DS.Color.inkSoft(0.3), trailing: true)
                }
                .padding(.top, 9)

                if let share = month.fixedShare {
                    Text("A bevételed \(Fmt.percentPlain(share))-a fix költség.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.5))
                        .padding(.top, 8)
                }
                runway(month)
            }
            .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Color.inkSoft(0.075)))
        }
    }

    private func legend(_ title: String, _ value: Decimal, _ color: Color,
                        trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 5) {
                if !trailing { Circle().fill(color).frame(width: 7, height: 7) }
                Text(title).font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.5))
                if trailing { Circle().fill(color).frame(width: 7, height: 7) }
            }
            Text(Fmt.huf(value)).font(DS.font(15, .semibold).monospacedDigit())
        }
    }

    /// Hány hónap fix költséget fedez a vagyonod.
    @ViewBuilder private func runway(_ month: SpendingAnalysis.Month) -> some View {
        if month.fixed > 0, store.grandTotalHUF > 0 {
            let months = (store.grandTotalHUF / month.fixed).doubleValue
            let liquid = store.grandTotalHUF - store.securitiesValueHUF
            Divider().padding(.vertical, 11)
            VStack(alignment: .leading, spacing: 3) {
                Text("A vagyonod \(Fmt.decimal(Decimal(months), max: 1)) hónap fix költséget fedez")
                    .font(DS.font(13, .medium))
                // A TBSZ-t eladni idő és adó; ezért külön kiírjuk, mennyi az,
                // amihez tényleg hozzáférsz holnap.
                if liquid > 0 {
                    Text("Ebből azonnal elérhető \(Fmt.huf(liquid)) — \(Fmt.decimal(Decimal((liquid / month.fixed).doubleValue), max: 1)) hónap.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Előfizetések

    private var recurring: [SpendingAnalysis.Recurring] {
        SpendingAnalysis.recurring(store.expenses)
    }

    @ViewBuilder private var recurringCard: some View {
        let items = recurring
        if !items.isEmpty {
            let yearly = items.reduce(Decimal(0)) { $0 + $1.yearly }
            Button { withAnimation(.easeOut(duration: 0.2)) { showRecurring.toggle() } } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        sectionLabel("ISMÉTLŐDŐ TERHELÉSEK")
                        Spacer()
                        Image(systemName: showRecurring ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Color.inkSoft(0.4))
                    }
                    Text(Fmt.huf(yearly))
                        .font(DS.font(24, .semibold).monospacedDigit())
                        .padding(.top, 4)
                    Text("\(items.count) állandó összegű terhelés, évesítve. Ezeket egyszer állítottad be.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)

                    if showRecurring {
                        VStack(spacing: 0) {
                            Divider().padding(.vertical, 10)
                            ForEach(items) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: item.category.icon)
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Color.inkSoft(0.45))
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.merchant).font(DS.font(13, .medium)).lineLimit(1)
                                        Text("\(item.months) hónapja · \(Fmt.huf(item.monthlyAverage))/hó")
                                            .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.4))
                                    }
                                    Spacer(minLength: 6)
                                    Text("\(Fmt.huf(item.yearly))/év")
                                        .font(DS.font(13, .medium).monospacedDigit())
                                }
                                .padding(.vertical, 7)
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Color.ink)
            .pastelCardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Color.inkSoft(0.075)))
        }
    }

    // MARK: - Emlékeztetők

    /// Ha a legutóbbi kivonat óta eltelt egy hónap, szólunk.
    @ViewBuilder private var importReminder: some View {
        if let newest = store.expenses.map(\.date).max(),
           let days = calendar.dateComponents([.day], from: newest, to: Date()).day,
           days >= 35 {
            banner(icon: "tray.and.arrow.down",
                   text: "\(days) napja nem olvastál be kivonatot. A Beállításokban tudod megtenni, vagy oszd meg ide a fájlt.",
                   tint: DS.Color.iconTime)
        }
    }

    /// A hitelkártya határideje. Csak akkor, ha még nem múlt el.
    @ViewBuilder private var cardDue: some View {
        if let card = store.creditCards.first(where: { !$0.isStale }),
           let days = card.daysUntilDue(), days <= 10 {
            banner(icon: "creditcard",
                   text: days == 0
                     ? "A hitelkártya fizetési határideje MA. Teljes tartozás \(Fmt.huf(card.totalDebt))."
                     : "\(days) nap múlva jár le a hitelkártya fizetési határideje. Teljes tartozás \(Fmt.huf(card.totalDebt))\(card.minimumPayment.map { ", minimum \(Fmt.huf($0))" } ?? "").",
                   tint: DS.Color.negativeCream)
        }
    }

    private func banner(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text(text)
                .font(DS.font(12.5, .regular))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private var footnote: some View {
        Text("A besorolás a kereskedő nevéből készül. Ami nem illik szabályra, „Egyéb” marad — nem tippelünk.")
            .font(DS.font(10.5, .regular))
            .foregroundStyle(DS.Color.inkSoft(0.36))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Még nincs beolvasott kivonat")
                .font(DS.font(15, .medium))
            Text("Oszd meg ide az OTP vagy a Revolut számlakivonatát (PDF vagy CSV), és a tételek innentől kategóriákra bontva látszanak.")
                .font(DS.font(12, .regular))
                .foregroundStyle(DS.Color.inkSoft(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 20)
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
