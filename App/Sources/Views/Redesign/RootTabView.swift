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
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        TabView {
            Tab("Portfólió", systemImage: "chart.pie.fill") {
                HomeView()
            }
            Tab("Hírek", systemImage: "newspaper.fill") {
                NewsView()
            }
            Tab("Kiadások", systemImage: "creditcard.fill") {
                ExpensesView()
            }
            Tab("Beállítások", systemImage: "gearshape.fill") {
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
