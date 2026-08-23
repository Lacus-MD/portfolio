import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct PortfolioWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(model)
        }
    }
}

/// Az óra oldali állapot. Nem számol semmit — a telefon küldi a kész számokat.
@MainActor
@Observable
final class WatchModel: NSObject, WCSessionDelegate {
    private(set) var summary: WatchSummary

    override init() {
        summary = WatchStore.load()
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Mennyire régi az adat. Az óra ezt kiírja, mert offline is mutat valamit,
    /// és a néma elavulás rosszabb, mint egy őszinte időbélyeg.
    var age: String? {
        guard let asOf = summary.asOf else { return nil }
        let minutes = Int(Date().timeIntervalSince(asOf) / 60)
        if minutes < 2 { return "most" }
        if minutes < 60 { return "\(minutes) perce" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) órája" }
        return "\(hours / 24) napja"
    }

    var isStale: Bool {
        guard let asOf = summary.asOf else { return true }
        return Date().timeIntervalSince(asOf) > 6 * 3600
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["summary"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSummary.self, from: data) else { return }
        Task { @MainActor in
            self.summary = decoded
            WatchStore.save(decoded)
            // A Smart Stack külön folyamat — külön kell szólni neki.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // Ezeket a callbackeket a watchOS nem használja, de az iOS SDK-s
    // szimulátoros ellenőrzés során a WCSessionDelegate kötelezővé teszi őket.
#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {}
#endif
}
