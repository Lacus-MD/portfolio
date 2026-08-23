import AppIntents
import Foundation

/// Parancsok-támogatás. Két művelet, szándékosan nem több: a „frissítés" és a
/// „kivonat beolvasása" fedi le azt, amit kívülről érdemes indítani.
/// A Parancsok appból innentől saját automatizálás építhető — például egy
/// gomb a kezdőképernyőre, ami egy fájlt ad át beolvasásra.

struct RefreshPortfolioIntent: AppIntent {
    static let title: LocalizedStringResource = "Portfólió frissítése"
    static let description = IntentDescription(
        "Begyűjti a kivonatokat az iCloud-mappából és a figyelt mappákból, majd frissíti az árfolyamokat.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Inbox.collectFromCloud()
        WatchedFolders.collect()
        return .result()
    }
}

struct ImportStatementIntent: AppIntent {
    static let title: LocalizedStringResource = "Kivonat beolvasása"
    static let description = IntentDescription(
        "Egy kivonat-fájlt (PDF vagy CSV) az app postaládájába tesz, és megnyitja az appot a feldolgozáshoz.")
    static let openAppWhenRun = true

    @Parameter(title: "Kivonat", supportedContentTypes: [.pdf, .commaSeparatedText, .plainText])
    var file: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        try Inbox.store(file.data, named: file.filename)
        return .result()
    }
}

struct PortfolioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RefreshPortfolioIntent(),
                    phrases: ["Frissítsd a \(.applicationName)t"],
                    shortTitle: "Frissítés",
                    systemImageName: "arrow.clockwise")
        AppShortcut(intent: ImportStatementIntent(),
                    phrases: ["Kivonat beolvasása a \(.applicationName)ba"],
                    shortTitle: "Kivonat beolvasása",
                    systemImageName: "tray.and.arrow.down")
    }
}
