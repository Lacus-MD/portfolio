import SwiftUI

/// A négy főnézet natív tab barban.
///
/// A „Platformok" fül 2026-08-22-én kikerült: minden, amit mutatott, a
/// kezdőképernyőn is megvan — a platformonkénti érték a kártyán, az összes
/// befizetés a fejlécben, az időbontás és a 100-ra indexált összevetés a
/// közös görbe alatt. Egy fül, ami ugyanazt mondja el máshogy, csak egy
/// hellyel több, ahol el lehet térni egymástól.
///
/// iOS 26-on a `TabView` magától Liquid Glass anyagot kap — nem kell utánozni.
/// Ezzel kiváltjuk a fejléc fehér menügombját és az alsó „összevetés" gombot is:
/// mindkettő egy-egy hely volt, nem művelet, tehát fülként a helyük.
struct RootTabView: View {
    @State private var selection: Destination = .portfolio

    private enum Destination: Hashable {
        case portfolio, news, expenses, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Portfólió", systemImage: "chart.pie.fill", value: .portfolio) {
                HomeView()
            }
            Tab("Hírek", systemImage: "newspaper.fill", value: .news) {
                NewsView(isActive: selection == .news)
            }
            Tab("Kiadások", systemImage: "creditcard.fill", value: .expenses) {
                ExpensesView()
            }
            Tab("Beállítások", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        // Nincs `.id(store.themeID)`. Az azonosító cseréje az EGÉSZ fát
        // újraépítette: a látvány olyan volt, mintha az app újraindulna, és
        // elveszett a görgetés meg a kiválasztott fül. A téma most
        // megfigyelhető (`ActiveTheme`), ezért a színolvasás magától
        // frissül — lásd a `DS.Color.theme` magyarázatát.
        .tint(DS.Color.coral)
    }
}
