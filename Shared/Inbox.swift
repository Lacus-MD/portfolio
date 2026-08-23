import Foundation

/// Az app és a kiterjesztései közös tárolójának azonosítója.
/// Külön áll, hogy a megosztás-kiterjesztés a modellek befordítása nélkül is
/// elérje. iOS-en a group-azonosító nem kap team-prefixet (macOS-en kapna).
enum AppGroup {
    static let id = "group.hu.halasz.portfolio"
}

/// Postaláda az App Group konténerben: ide teszi a megosztás-kiterjesztés a
/// kapott fájlt, és innen olvassa be az app induláskor.
///
/// Szándékosan NEM függ a modellektől, csak a Foundationtől — így a
/// megosztás-kiterjesztésbe nem kell befordítani az egész adatréteget.
/// A kiterjesztés külön folyamat, rövid életű, és nem tud hálózatot hívni
/// kényelmesen; ezért csak lerakja a fájlt, a feldolgozást az app végzi.
enum Inbox {
    static var directory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
        else { return nil }
        let inbox = container.appending(path: "inbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    /// Elmenti a fájlt a postaládába. **A fájlnevet megőrizzük**, mert a
    /// számlaazonosító abból derül ki (`AccountStatement-LY-4WY38ZH-…`).
    /// Névütközésnél sorszámozunk, nem írunk felül.
    @discardableResult
    static func store(_ data: Data, named name: String) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = directory.appending(path: suffix)
            counter += 1
        }
        try data.write(to: candidate, options: .atomic)
        return candidate
    }

    /// A feldolgozásra váró fájlok, régebbitől újabbig.
    static func pending() -> [URL] {
        guard let directory,
              let items = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return items.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - iCloud-mappa

    static let ubiquityContainerID = "iCloud.hu.halasz.portfolio"

    /// A Fájlok appban látható „Portfólió" mappa. Ide Macről is bedobhatsz
    /// kivonatot, és az app a következő indításkor beolvassa.
    static var cloudDocuments: URL? {
        guard let container = FileManager.default
            .url(forUbiquityContainerIdentifier: ubiquityContainerID) else { return nil }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        placeReadme(in: documents)
        return documents
    }

    /// Egy rövid útmutató a mappába.
    ///
    /// **Nem díszítés: enélkül a mappa meg sem jelenik.** Az iOS a Fájlok
    /// appban nem mutatja az app ÜRES iCloud-mappáját, tehát hiába hoztuk
    /// létre a könyvtárat, a felhasználó nem látta. Egy fájl kell bele.
    /// (A másik feltétel a build-szám növelése: az `NSUbiquitousContainers`
    /// beállítást az iOS gyorsítótárazza, és csak új verziónál olvassa újra.)
    private static func placeReadme(in documents: URL) {
        let url = documents.appending(path: "Ide dobd a kivonatokat.txt")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let text = """
        Portfólió — kivonatok mappája

        Ide másolhatod a számlakivonataidat, akár Macről is. Az app a
        következő indításkor beolvassa őket, és a fájlt elviszi innen.

        Amit ért:
          • OTP bankszámla- és hitelkártya-kivonat (PDF)
          • Revolut folyószámla- és megtakarítási kivonat (CSV)
          • Lightyear számlakivonat (CSV)
          • Államkincstár portfólió-export (CSV/TXT)

        A fájlok nem mennek sehova: a feldolgozás a készülékeden történik.
        """
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Áthozza az iCloud-mappából a postaládába, ami újként odakerült.
    ///
    /// Az iCloud lusta: a fájl előbb csak „elérhető"-ként jelenik meg, a
    /// tartalma nincs letöltve. Ezért kérni kell a letöltését, és csak a
    /// ténylegesen jelen lévő fájlokat mozgatjuk — a többi majd a következő
    /// indításkor kerül sorra. Ez nem hiba, hanem az iCloud működése.
    @discardableResult
    static func collectFromCloud() -> Int {
        guard let documents = cloudDocuments,
              let items = try? FileManager.default.contentsOfDirectory(
                at: documents,
                includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
              ) else { return 0 }

        // A kivonatok ma már PDF-ben is jönnek (az OTP lakossági kivonata csak
        // úgy). Korábban csak a CSV-t vettük át, ezért a mappába dobott PDF
        // csendben ottmaradt.
        let accepted = ["csv", "pdf", "txt", "xml"]
        var moved = 0
        for url in items where accepted.contains(url.pathExtension.lowercased()) {
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                .ubiquitousItemDownloadingStatus
            if status == .notDownloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard (try? store(data, named: url.lastPathComponent)) != nil else { continue }
            archive(url)
            moved += 1
        }
        return moved
    }

    /// A feldolgozott fájl a „Feldolgozva" almappába kerül, NEM törlődik.
    ///
    /// Korábban töröltük, de a Mac-oldali figyelővel együtt ez azt
    /// jelentette volna, hogy a kivonatod eredetije eltűnik: a figyelő
    /// elviszi a Letöltésekből, az app meg kitörli az iCloudból. Egy
    /// bankkivonat archívum-érték — a felhasználó fájljait nem dobjuk ki.
    static func archive(_ url: URL) {
        guard let documents = cloudDocuments else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let folder = documents.appending(path: "Feldolgozva", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var target = folder.appending(path: url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let base = (url.lastPathComponent as NSString).deletingPathExtension
            let ext = url.pathExtension
            target = folder.appending(path: "\(base)-\(counter).\(ext)")
            counter += 1
        }
        // Ha a mozgatás nem megy (pl. másik kötetről), másolás + törlés.
        if (try? FileManager.default.moveItem(at: url, to: target)) == nil {
            try? FileManager.default.copyItem(at: url, to: target)
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Kivonat-fájlnevek

    /// Igaz, ha a fájlnév ismert kivonat-mintára illik.
    ///
    /// A felhasználó által kijelölt mappákban (pl. az iCloud Drive gyökere)
    /// CSAK ilyen nevű fájlokhoz nyúlunk — egy általános mappából mindent
    /// behúzni turkálás volna, és hibafolyamot adna minden idegen CSV-re.
    /// A saját „Portfólió" mappánkban viszont minden elfogadott kiterjesztésű
    /// fájl játszik: azt a mappát kifejezetten erre adtuk.
    static func looksLikeStatement(_ name: String) -> Bool {
        let normalized = name.lowercased().folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: .current
        )
        let patterns = [
            "^Bankszámlakivonat_",           // OTP bankszámla
            "^Hitelkártya számlakivonat_",   // OTP hitelkártya
            "^savings-statement_",           // Revolut megtakarítás
            "^account-statement_",           // Revolut folyószámla
            "^accountstatement-ly-",         // Lightyear
            "^allamkincstar",               // Államkincstár
            "^allampap",                    // Állampapír export
            "^webkincstar",                 // Webkincstár export
        ]
        return patterns.contains { normalized.range(of: $0, options: .regularExpression) != nil }
    }
}
