import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct PortfolioApp: App {
    @State private var store = PortfolioStore()
    @State private var banking = EnableBankingService()
    @State private var cloudWatcher: CloudWatcher?
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTaskID = "hu.halasz.portfolio.refresh"

    /// Az ÉLŐ példányok, ha az app fut. A háttérfeladat ezeket használja;
    /// ha nincsenek (hidegen, csak a feladat kedvéért indított app), akkor
    /// gyárt magának — olyankor nincs másik példány, amit felülírhatna.
    @MainActor private static var live: (store: PortfolioStore,
                                         banking: EnableBankingService)?

    init() {
        // A frissítés közben talált nagy mozgás előtérben is látható legyen.
        UNUserNotificationCenter.current().delegate = PortfolioNotificationDelegate.shared
        // Korán aktiválunk: a párosítás felépítése időbe telik, és az első
        // mentés már működő munkamenetet találjon.
        WatchBridge.shared.activate()
        Self.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            // A betöltés a store init-jében történik, nem itt: két párhuzamos
            // `.task` sorrendje nem garantált, és a vesztes esetben üres
            // állapot íródott a lemezre.
            RootTabView()
                .environment(store)
                .environment(banking)
                // Fájlokból / Mailből „Megnyitás — Portfólió". Az iOS a
                // fájlt bemásolja az app Documents/Inbox-ába (nincs
                // open-in-place), ezért itt csak a saját postaládánkba
                // tesszük át és feldolgozzuk.
                .onOpenURL { url in
                    // A banki jóváhagyás visszatérése a böngészőből.
                    //
                    // Az appon BELÜLI folyamathoz ez nem kell — ott a
                    // beágyazott ablak a betöltés ELŐTT elkapja a kódot.
                    // Ha viszont a jóváhagyás a vezérlőpultról indult
                    // (Safariban), a kód a GitHub Pages oldalunkra érkezik,
                    // és onnan egy gombbal adható át ide — különben elveszne.
                    if url.scheme == "portfolio" {
                        banking.finishAuthentication(.success(url))
                        return
                    }
                    guard url.isFileURL else { return }
                    Task { [store] in
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        if let data = try? Data(contentsOf: url) {
                            try? Inbox.store(data, named: url.lastPathComponent)
                            try? FileManager.default.removeItem(at: url)
                        }
                        await store.startup()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // KORÁBBI RÉS: a postaláda csak hidegindításkor ürült.
                // Ha az app a háttérben futott, és megosztottál egy fájlt,
                // a visszaváltás után semmi nem történt. Most minden
                // előtérbe kerülés feldolgoz — a hívás olcsó, ha üres.
                Task { [store, banking] in
                    await store.startup()
                    // A banki folyószámlák frissítése. Saját várakozási
                    // ideje van (6 óra), tehát ez a hívás olcsó, ha nem kell.
                    await banking.syncIfStale(store: store)
                }
                // A háttérfeladat innen tudja, MELYIK példányokat használja.
                // Enélkül másodpéldányt kellene gyártania, és a felfüggesztett
                // app visszatérésekor felülírná a háttérben mentett munkát.
                Self.live = (store, banking)
                if cloudWatcher == nil {
                    // Élő figyelő a saját iCloud-mappán: amíg előtérben
                    // vagyunk, a Macről bedobott fájl magától beolvasódik.
                    cloudWatcher = CloudWatcher { [store] in
                        Task { await store.startup() }
                    }
                }
            case .background:
                Self.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }

    // MARK: - Háttérfrissítés

    /// Napi egy háttér-lehetőséget kérünk: begyűjtjük az iCloud-mappát és
    /// újraütemezzük a kártya-emlékeztetőt.
    ///
    /// Őszintén: az iOS a futtatást NEM garantálja — a rendszer a használati
    /// mintád alapján dönt. Ez kényelmi réteg; a gerinc továbbra is az
    /// előtérbe kerülés és a widget napi mérése.
    private static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID,
                                        using: nil) { task in
            scheduleBackgroundRefresh()
            let work = Task { @MainActor in
                Inbox.collectFromCloud()
                WatchedFolders.collect()
                let payload = PortfolioFile.load()
                await PaymentReminder.schedule(for: payload.creditCards.first)
                await Reminders.Statements.schedule()

                // A bankkapcsolat frissítése. A kulcs `AfterFirstUnlock`
                // hozzáférésű, tehát a Keychainból háttérben is olvasható —
                // az első feloldás után. Zárolt telefonon frissen indított
                // eszközön kimarad, és az nem baj: legközelebb megy.
                let pair = live ?? (PortfolioStore(), EnableBankingService())
                // A napi háttérlehetőség a piaci mozgásokat is ellenőrzi.
                // Az iOS időpontot nem garantál, de ehhez nem kell nyitva
                // hagyni az appot.
                await pair.store.refresh()
                await pair.banking.syncIfStale(store: pair.store)

                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    private static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
