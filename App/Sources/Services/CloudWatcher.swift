import Foundation

/// Élő figyelő az app saját iCloud-mappáján.
///
/// Amíg az app előtérben van, a Macről (vagy a Fájlokból) bedobott fájl
/// magától megérkezik — nem kell hozzá újraindítás. Az `NSMetadataQuery` a
/// ubiquity-konténert figyeli; a találatokra a tár postaláda-feldolgozását
/// hívjuk, tömörítve (fél másodperces összevonással), mert az iCloud egy
/// letöltés közben többször is jelez.
@MainActor
final class CloudWatcher {

    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Csak olyan fájl változása érdekel, amit tényleg be tudunk olvasni.
        // A korábbi `LIKE '*'` minden iCloud-metaadat változásnál felébresztette
        // az appot (README, archív mappa, szinkronállapot), és a főszálon újra
        // elindította a teljes postaláda-vizsgálatot görgetés közben is.
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            "csv", "pdf", "txt", "xml"
        ].map { ext in
            NSPredicate(format: "%K ENDSWITH[c] %@", NSMetadataItemFSNameKey, ".\(ext)")
        })

        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering,
                     .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: query, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.debouncedChange() }
            })
        }
        query.start()
    }

    private func debouncedChange() {
        pending?.cancel()
        pending = Task { [onChange] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            onChange()
        }
    }

    deinit {
        query.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
