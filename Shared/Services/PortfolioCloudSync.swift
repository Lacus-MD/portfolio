import Foundation

/// Cross-device portfolio synchronisation backed by the app's iCloud
/// Documents container.
///
/// This deliberately uses a separate file from statement imports. The app
/// can therefore keep archiving imported PDFs/CSVs without ever treating the
/// synchronised portfolio snapshot as an input statement. Bank credentials
/// and consent tokens remain in Keychain and are never part of this payload.
enum PortfolioCloudSync {
    static let fileName = Inbox.portfolioSyncFileName

    private static let revisionDateKey = "portfolio.cloudSync.revisionDate"
    private static let revisionDeviceKey = "portfolio.cloudSync.revisionDevice"
    private static let deviceIDKey = "portfolio.cloudSync.deviceID"
    private static let appGroupDefaults = "group.hu.halasz.portfolio"

    /// The on-disk envelope is intentionally self-describing so future
    /// releases can reject or migrate it without guessing its shape.
    struct Envelope: Codable, @unchecked Sendable {
        let schemaVersion: Int
        let updatedAt: Date
        let deviceID: String
        let payload: PortfolioFile.Payload

        init(schemaVersion: Int = PortfolioFile.currentSchemaVersion,
             updatedAt: Date,
             deviceID: String,
             payload: PortfolioFile.Payload) {
            self.schemaVersion = schemaVersion
            self.updatedAt = updatedAt
            self.deviceID = deviceID
            self.payload = payload
        }
    }

    /// Result of attempting to publish a local snapshot. A newer remote
    /// snapshot is returned instead of being overwritten; the caller can
    /// apply it and persist it locally.
    enum PushResult: @unchecked Sendable {
        case written(Envelope)
        case remoteNewer(Envelope)
        case unavailable
        case failed(String)
    }

    /// Small injectable file adapter used by tests and future storage
    /// backends. Production reads/writes use the coordinated variants below.
    struct FileStore {
        let url: URL
        let fileManager: FileManager

        init(url: URL, fileManager: FileManager = .default) {
            self.url = url
            self.fileManager = fileManager
        }

        func read() throws -> Envelope? {
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard !data.isEmpty else { return nil }
            return try PortfolioCloudSync.decodeEnvelope(data)
        }

        func write(_ envelope: Envelope) throws {
            let data = try JSONEncoder().encode(envelope)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupDefaults) ?? .standard
    }

    private static var deviceID: String {
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: deviceIDKey)
        return generated
    }

    private static var cloudURL: URL? {
        Inbox.cloudDocuments?.appending(path: fileName)
    }

    /// A revision is ordered by timestamp, with the device ID as a stable
    /// tie-breaker for two writes made in the same clock tick.
    static func isNewer(_ lhs: Envelope, than rhs: Envelope) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.deviceID > rhs.deviceID
    }

    /// Returns a remote snapshot only when it is newer than the last snapshot
    /// this device successfully pulled or published.
    static func pullIfNewer() -> Envelope? {
        guard let url = cloudURL, prepareForRead(url) else { return nil }
        guard let remote = coordinatedRead(url) else { return nil }
        guard let localRevision = lastSyncedRevision else {
            // A newly installed device has no local revision. The existing
            // cloud snapshot is authoritative and is pulled before the first
            // local save, preventing an accidental overwrite.
            return remote
        }
        return isNewer(remote, than: localRevision) ? remote : nil
    }

    /// Publishes a snapshot unless the remote file changed after this device's
    /// last sync. In that case the remote version wins and is surfaced to the
    /// caller rather than silently losing another device's edits.
    static func push(_ payload: PortfolioFile.Payload,
                     now: Date = Date()) -> PushResult {
        guard let url = cloudURL else { return .unavailable }
        if FileManager.default.fileExists(atPath: url.path) {
            guard prepareForRead(url) else { return .unavailable }
            if let remote = coordinatedRead(url) {
                guard let localRevision = lastSyncedRevision else {
                    return .remoteNewer(remote)
                }
                if isNewer(remote, than: localRevision) {
                    return .remoteNewer(remote)
                }
            }
        }

        let envelope = Envelope(updatedAt: now, deviceID: deviceID, payload: payload)
        do {
            try coordinatedWrite(envelope, to: url)
            markSynced(envelope)
            return .written(envelope)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Records a remote revision after it has been applied locally.
    static func markPulled(_ envelope: Envelope) {
        markSynced(envelope)
    }

    static var lastSyncedAt: Date? {
        defaults.object(forKey: revisionDateKey) as? Date
    }

    private static var lastSyncedRevision: Envelope? {
        guard let date = defaults.object(forKey: revisionDateKey) as? Date,
              let device = defaults.string(forKey: revisionDeviceKey) else {
            return nil
        }
        return Envelope(updatedAt: date, deviceID: device, payload: PortfolioFile.Payload())
    }

    private static func markSynced(_ envelope: Envelope) {
        defaults.set(envelope.updatedAt, forKey: revisionDateKey)
        defaults.set(envelope.deviceID, forKey: revisionDeviceKey)
    }

    private static func decodeEnvelope(_ data: Data) throws -> Envelope {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion <= PortfolioFile.currentSchemaVersion else {
            throw NSError(domain: "PortfolioCloudSync", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported portfolio sync schema version"
            ])
        }
        return envelope
    }

    /// iCloud files can appear as a placeholder before their bytes are
    /// downloaded. Requesting the download and waiting for the next metadata
    /// notification is safer than decoding a partial file.
    private static func prepareForRead(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard let status = try? url.resourceValues(
            forKeys: [.ubiquitousItemDownloadingStatusKey]
        ).ubiquitousItemDownloadingStatus else { return true }
        if status == .notDownloaded {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return false
        }
        return true
    }

    private static func coordinatedRead(_ url: URL) -> Envelope? {
        var data: Data?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            data = try? Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
        }
        guard coordinationError == nil, let data, !data.isEmpty else { return nil }
        return try? decodeEnvelope(data)
    }

    private static func coordinatedWrite(_ envelope: Envelope, to url: URL) throws {
        let data = try JSONEncoder().encode(envelope)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        var writeError: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let writeError { throw writeError }
        if let coordinationError { throw coordinationError }
    }
}

/// Serialises iCloud writes so two quick saves cannot race each other or
/// publish an older snapshot after a newer one.
actor PortfolioCloudSyncWriter {
    static let shared = PortfolioCloudSyncWriter()

    func push(_ payload: PortfolioFile.Payload) -> PortfolioCloudSync.PushResult {
        PortfolioCloudSync.push(payload)
    }
}
