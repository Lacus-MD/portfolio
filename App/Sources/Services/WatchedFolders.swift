import Foundation

/// A felhasználó által kijelölt mappák figyelése — így „lát" az app az
/// iCloud Drive-ba is.
///
/// Az iOS-sandbox miatt az app magától nem olvashatja a Drive-ot. A járható
/// út: a mappaválasztóban EGYSZER kijelölsz egy mappát, arról biztonsági
/// könyvjelzőt tárolunk, és onnantól minden előtérbe kerüléskor átnézzük.
/// A kijelölt mappából CSAK az ismert kivonat-nevű fájlokat vesszük el
/// (`Inbox.looksLikeStatement`) — egy általános mappából mindent behúzni
/// turkálás volna.
enum WatchedFolders {

    private static let bookmarksKey = "watchedFolderBookmarks"
    private static let processedKey = "watchedFolderProcessed"

    // MARK: - Könyvjelzők

    static var urls: [URL] {
        bookmarks.compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        }
    }

    private static var bookmarks: [Data] {
        get { UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: bookmarksKey) }
    }

    static func add(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData() else { return }
        // Ugyanazt a mappát nem vesszük fel kétszer.
        guard !urls.contains(where: { $0.path == url.path }) else { return }
        bookmarks.append(bookmark)
    }

    static func remove(at index: Int) {
        var list = bookmarks
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        bookmarks = list
    }

    // MARK: - Gyűjtés

    /// Átnézi a figyelt mappákat, és a kivonat-mintájú fájlokat a postaládába
    /// másolja. A feldolgozott fájlokat NEM mozdítjuk el — az a felhasználó
    /// mappája, nem a miénk. Helyette jegyezzük, mit láttunk már
    /// (név + méret + módosítási idő), hogy ne olvassuk be újra.
    @discardableResult
    static func collect() -> Int {
        var moved = 0
        var processed = Set(UserDefaults.standard.stringArray(forKey: processedKey) ?? [])

        for folder in urls {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

            guard let items = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey,
                                             .ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]) else { continue }

            for url in items where Inbox.looksLikeStatement(url.lastPathComponent) {
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey,
                    .ubiquitousItemDownloadingStatusKey])

                // iCloud-lustaság: kérjük a letöltést, majd a következő
                // körben jön — most nem tudjuk beolvasni.
                if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    continue
                }

                let key = "\(url.lastPathComponent)|\(values?.fileSize ?? 0)|" +
                    "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                guard !processed.contains(key) else { continue }
                guard let data = try? Data(contentsOf: url) else { continue }
                guard (try? Inbox.store(data, named: url.lastPathComponent)) != nil else { continue }
                processed.insert(key)
                moved += 1
            }
        }
        // A jegyzék ne nőjön korlátlanul — pár száz kivonatnál több nem lesz.
        UserDefaults.standard.set(Array(processed.suffix(500)), forKey: processedKey)
        return moved
    }
}
