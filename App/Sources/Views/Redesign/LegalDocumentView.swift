import SwiftUI

/// Az appon belüli, natív jogi tájékoztatók.
///
/// A GitHub Pages-en lévő HTML-oldalak a külső banki regisztrációhoz és a
/// publikus jogi URL-ekhez továbbra is szükségesek, de a felhasználó ezeket
/// az alkalmazásban is el tudja olvasni WebView nélkül.
enum LegalDocument: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return "Adatkezelés"
        case .terms: return "Felhasználási feltételek"
        }
    }

    var effectiveDate: String { "Hatályos: 2026. augusztus 22." }

    var sections: [(title: String, body: String)] {
        switch self {
        case .privacy:
            return [
                ("Ki kezeli az adatokat", "A Portfólió egyetlen magánszemély saját használatára készült iOS-alkalmazás. Az adatkezelő maga a felhasználó; az alkalmazásnak nincs üzemeltetője, nincs szervere, és nincsenek más felhasználói."),
                ("Milyen adatokat kezel", "Bankszámla- és értékpapírszámla-egyenlegek, tranzakciók, számlakivonatokból beolvasott tételek (PDF, CSV), valamint nyilvános árfolyam- és hírforrásokból lekért adatok."),
                ("Hol tárolódnak", "Kizárólag a felhasználó saját készülékén, illetve a felhasználó saját iCloud-tárhelyén. Az alkalmazás nem továbbít pénzügyi adatot saját kiszolgálóra."),
                ("Harmadik felek", "Ha a felhasználó bekapcsolja a nyílt banki összekötést, az adatok a bank és a készülék között az Enable Banking Oy infrastruktúráján keresztül haladnak. Az alkalmazás kizárólag olvasási hozzáférést kér; fizetés indítására nem alkalmas. A hozzájárulás a bank felületén visszavonható, és legfeljebb 180 nap után lejár."),
                ("Megőrzés és törlés", "Az adatok addig maradnak meg, amíg a felhasználó törli őket az alkalmazásból, vagy eltávolítja az alkalmazást a készülékéről."),
                ("Kapcsolat", "l.halasz@pm.me")
            ]
        case .terms:
            return [
                ("Az alkalmazás jellege", "A Portfólió magáncélú, egyfelhasználós alkalmazás, amelyet a készítője a saját pénzügyeinek követésére használ. Nem nyilvános szolgáltatás, és nincs harmadik fél felhasználója."),
                ("Nem pénzügyi tanácsadás", "Az alkalmazás kizárólag a felhasználó saját, meglévő adatait jeleníti meg és összesíti. Nem ad befektetési, adózási vagy pénzügyi tanácsot; a megjelenített számok tájékoztató jellegűek."),
                ("Nyílt banki hozzáférés", "A banki összekötés kizárólag számlainformációs, olvasási hozzáférés a felhasználó saját számláira, kifejezett banki jóváhagyással. Fizetés indítására az alkalmazás nem alkalmas."),
                ("Felelősség", "Az alkalmazás „ahogy van” állapotban működik, garancia nélkül. A hiteles adat mindig a bank vagy a szolgáltató saját kimutatása."),
                ("Kapcsolat", "l.halasz@pm.me")
            ]
        }
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        List {
            Section {
                Text(document.effectiveDate)
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.55))
            }

            ForEach(Array(document.sections.enumerated()), id: \.offset) { item in
                Section(item.element.title) {
                    Text(item.element.body)
                        .font(DS.font(14, .regular))
                        .foregroundStyle(DS.Color.ink)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Color.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
