import Foundation
import WatchConnectivity

/// Telefon → óra híd.
///
/// `updateApplicationContext`-et használ, nem üzenetet: ez mindig a LEGFRISSEBB
/// állapotot tartja, felülírja az előzőt, és akkor is kézbesít, ha az óra épp
/// nem elérhető — a rendszer megvárja. Egy vagyonkijelzőnek pontosan erre van
/// szüksége: nem az események sorrendje számít, hanem a mostani állapot.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func send(_ summary: WatchSummary) {
        guard let session, session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(summary) else { return }
        // A szótár értékeinek property-list-kompatibilisnek kell lenniük,
        // ezért egyetlen Data mezőt küldünk, nem szétbontott számokat.
        try? session.updateApplicationContext(["summary": data])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {}
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
