import Foundation

/// File-system backed storage with injectable locations for deterministic
/// migration and recovery tests. `PortfolioFile` remains the app façade.
extension PortfolioFile {
    struct Storage {
        let mainURL: URL
        let backupURL: URL
        let legacyURL: URL?
        let fileManager: FileManager

        init(mainURL: URL, backupURL: URL, legacyURL: URL? = nil,
             fileManager: FileManager = .default) {
            self.mainURL = mainURL
            self.backupURL = backupURL
            self.legacyURL = legacyURL
            self.fileManager = fileManager
        }

        func save(_ payload: Payload) throws {
            let data = try JSONEncoder().encode(payload)
            try fileManager.createDirectory(at: mainURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try data.write(to: mainURL, options: .atomic)
            if !payload.holdings.isEmpty {
                try data.write(to: backupURL, options: .atomic)
            }
        }

        func loadDetailed() -> (payload: Payload, status: LoadStatus) {
            if let payload = decode(mainURL) { return (payload, .ok) }
            let mainExists = fileManager.fileExists(atPath: mainURL.path)

            if let payload = decode(backupURL) {
                if mainExists {
                    let broken = mainURL.deletingLastPathComponent()
                        .appendingPathComponent("portfolio.broken.json")
                    try? fileManager.removeItem(at: broken)
                    try? fileManager.moveItem(at: mainURL, to: broken)
                }
                try? save(payload)
                return (payload, .recovered)
            }

            if let legacyURL, let payload = decode(legacyURL) {
                try? save(payload)
                return (payload, .ok)
            }

            return (Payload(), mainExists ? .corrupt : .missing)
        }

        private func decode(_ url: URL) -> Payload? {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
            return try? PortfolioFile.decodePayload(data)
        }
    }
}
