import SwiftUI

/// „Mi lenne, ha…" — kamatos-kamat számoló a te feltevéseiddel.
struct ScenarioView: View {
    @Environment(PortfolioStore.self) private var store

    @State private var annualReturn: Double = 6
    @State private var monthly: String = "100 000"
    @State private var target: Date = Date()
    /// Igaz, amint a mentett feltevések betöltődtek. Enélkül a kezdeti
    /// értékadás azonnal felülírná a mentést az alapértékekkel.
    @State private var loaded = false

    private var parsedMonthly: Decimal {
        let cleaned = monthly
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private var result: ScenarioResult {
        ScenarioCalculator.project(
            currentHUF: store.grandTotalHUF,
            scenario: Scenario(annualReturnPct: annualReturn,
                               monthlyHUF: parsedMonthly, targetDate: target)
        )
    }

    var body: some View {
        // NEM `NavigationStack` és NEM lap: a hívó NAVIGÁL ide. Így teljes
        // magasságú, és a natív oldalra-húzós vissza-gesztus jár hozzá —
        // lapként lefelé kellett volna elhúzni, és a lap alapból alacsonyabb
        // is volt, ezért az eredményhez görgetni kellett.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                disclaimer
                inputs
                outcome
                breakdown
            }
            .padding(20)
            // A lebegő fül-sáv ráúszik a tartalomra, ezért kap helyet.
            .padding(.bottom, 96)
            .readableWidth()
        }
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .navigationTitle("Mi lenne, ha…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // A feltevések MENTÉSE nem külön gomb dolga — de nem is a
        // `.onDisappear`-é: kimértem, hogy a natív vissza-gesztussal
        // kilépve nem futott le, és a beállításaid nyom nélkül elvesztek
        // (a tárolt állományban meg sem jelent a kulcs). Minden változásnál
        // mentünk; ez néhány apró írás, cserébe nincs mit elveszíteni.
        .onChange(of: annualReturn) { persist() }
        .onChange(of: monthly) { persist() }
        .onChange(of: target) { persist() }
        .tint(DS.Color.coral)
        .onAppear {
            let saved = store.scenario
            annualReturn = saved?.annualReturnPct ?? 6
            monthly = Fmt.decimal(saved?.monthlyHUF ?? 100_000, max: 0)
            target = saved?.targetDate ?? store.defaultScenarioTarget
            loaded = true
        }
    }

    private func persist() {
        guard loaded else { return }
        store.setScenario(Scenario(annualReturnPct: annualReturn,
                                   monthlyHUF: parsedMonthly,
                                   targetDate: target))
    }

    /// Ez nem díszítés: a szám csak akkor őszinte, ha oda van írva, hogy feltevés.
    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.system(size: 13))
            Text("Ez nem előrejelzés. Senki nem tudja, mennyit hoz egy világindex — a feltevéseket te adod meg, az app csak kiszámolja, mi következne belőlük.")
                .font(DS.font(11.5, .regular))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DS.Color.inkSoft(0.6))
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Feltételezett éves hozam").font(DS.rowTitle)
                    Spacer()
                    Text(Fmt.percentPlain(annualReturn))
                        .font(DS.font(15, .semibold).monospacedDigit())
                        .foregroundStyle(DS.Color.coral)
                }
                Slider(value: $annualReturn, in: -5...15, step: 0.5)
                Text("Negatívat is beállíthatsz — a veszteséges forgatókönyv ugyanolyan érvényes kérdés.")
                    .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Havi befizetés").font(DS.rowTitle)
                TextField("100 000", text: $monthly)
                    .keyboardType(.numberPad)
                    .font(DS.font(17, .medium))
                    .padding(12)
                    .pastelCardBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Meddig", selection: $target,
                           in: Date()..., displayedComponents: .date)
                    .font(DS.rowTitle)
                Text("Alapértelmezésben a TBSZ-ed adómentessé válásának napja.")
                    .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.5))
            }
        }
    }

    private var outcome: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Akkor \(Fmt.day(target))-én")
                .font(DS.label).foregroundStyle(DS.Color.inkSoft(0.5))
            Text(Fmt.huf(result.total))
                .font(DS.font(34, .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(result.months) hónap múlva")
                .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(DS.Color.coral.opacity(0.18), in: .rect(cornerRadius: DS.R.platformCard))
    }

    /// A bontás a lényeg: mennyi belőle a saját pénzed és mennyi a feltételezett hozam.
    private var breakdown: some View {
        VStack(spacing: 0) {
            row("Amit ma már megvan", store.grandTotalHUF)
            Divider().padding(.leading, 16)
            row("Amit még beteszel", result.contributed)
            Divider().padding(.leading, 16)
            row("A feltételezett hozam", result.earned, emphasise: true)
        }
        .pastelCardBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ title: String, _ value: Decimal, emphasise: Bool = false) -> some View {
        HStack {
            Text(title).font(DS.rowTitle)
            Spacer()
            Text(Fmt.huf(value))
                .font(DS.font(13.5, emphasise ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(emphasise ? DS.Color.coral : DS.Color.ink)
        }
        .padding(16)
    }
}
