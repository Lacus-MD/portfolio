import SwiftUI

/// „Mi történik, ha lejár?” — a banki hozzájárulás élettartama és a teendő.
///
/// Külön oldal, mert a Bankkapcsolat lapon ez lábjegyzetként elveszne, a
/// lejárat pedig fél évente egyszer jön elő: pont akkor, amikor már nem
/// emlékszel a részletekre.
struct BankConsentInfoView: View {
    @Environment(EnableBankingService.self) private var banking

    private let maxDays = 180

    var body: some View {
        List {
            Section {
                ForEach(banking.connections) { connection in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connection.bankName).font(DS.rowTitle)
                        Text(statusText(for: connection))
                            .font(DS.meta)
                            .foregroundStyle(tint(for: connection))
                    }
                    .padding(.vertical, 2)
                }
                if banking.connections.isEmpty {
                    Text("Még nincs összekötött bank.")
                        .font(DS.meta)
                        .foregroundStyle(DS.Color.inkSoft(0.5))
                }
            } header: {
                Text("Jelenlegi állapot")
            }

            Section {
                step(1, "Beállítások → Bankkapcsolat")
                step(2, "„Bank összekapcsolása” — válaszd ki ugyanazt a bankot")
                step(3, "A bank jóváhagyó oldala az appon belül nyílik: lépj be, és engedélyezd újra")
                step(4, "Kész — a lejárt kapcsolatot húzd balra, és válaszd a Leválasztást")
            } header: {
                Text("Amit lejáratkor tenned kell")
            } footer: {
                Text("Nagyjából egy perc, és pontosan ugyanaz, mint az első összekötés. "
                   + "Új kulcs, új regisztráció, a vezérlőpult megnyitása NEM kell hozzá.")
            }

            Section {
                fact("Nem vész el adat", "A már letöltött tranzakciók és egyenlegek a telefonon maradnak. A lejárat csak azt jelenti, hogy ÚJAT nem tudok lekérni.")
                fact("Nem jár le a beállítás", "Az Enable Banking alkalmazásod és a privát kulcs érvényes marad. Csak a banki hozzájárulás jár le, bankonként külön.")
                fact("Előre szólok", "A Bankkapcsolat oldal kiírja, hány nap van hátra, és — ha bekapcsolod — egy héttel előbb értesítést is kapsz.")
            } header: {
                Text("Amitől nem kell tartanod")
            }

            Section {
                Text("A banki hozzájárulás a jogszabály szerint legfeljebb \(maxDays) napig élhet, "
                   + "és ezt a bank nem tudja meghosszabbítani — csak te tudod újra megadni. "
                   + "Az OTP és a Revolut is a teljes \(maxDays) napot adja.")
                    .font(DS.meta)
                Text("Ez ugyanaz a szabály, ami miatt a bank saját appja is időnként újra bekéri a jelszavadat: "
                   + "a hozzáférés szándékosan nem lehet örökös.")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.5))
            } header: {
                Text("Miért van egyáltalán lejárat")
            }

            Section {
                Text("A megtakarítási és a hitelkártya-számla nem esik a PSD2 hatálya alá, "
                   + "ezért azokat a bank nem adja ki így — ott marad a kivonat beolvasása. "
                   + "Ez a lejárattól függetlenül igaz.")
                    .font(DS.meta)
            } header: {
                Text("Ami továbbra is kivonatból jön")
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .navigationTitle("Ha lejár az engedély")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Részletek

    private func daysLeft(_ connection: EnableBankingService.EBConnection) -> Int? {
        guard let until = connection.validUntil else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: until).day
    }

    private func statusText(for connection: EnableBankingService.EBConnection) -> String {
        guard let days = daysLeft(connection), let until = connection.validUntil else {
            return "A lejárat ismeretlen — a következő frissítés után derül ki."
        }
        if days < 0 { return "Lejárt \(-days) napja — kösd össze újra." }
        if days == 0 { return "MA jár le." }
        return "\(days) nap van hátra · \(until.formatted(date: .abbreviated, time: .omitted))"
    }

    private func tint(for connection: EnableBankingService.EBConnection) -> Color {
        guard let days = daysLeft(connection) else { return DS.Color.inkSoft(0.5) }
        if days <= 0 { return DS.Color.negativeCream }
        if days <= 14 { return DS.Color.iconTime }
        return DS.Color.inkSoft(0.5)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(DS.meta.weight(.semibold))
                .foregroundStyle(DS.Color.inkSoft(0.45))
                .frame(width: 16, alignment: .trailing)
            Text(text).font(DS.rowTitle)
        }
        .padding(.vertical, 1)
    }

    private func fact(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DS.rowTitle)
            Text(body).font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.55))
        }
        .padding(.vertical, 2)
    }
}
