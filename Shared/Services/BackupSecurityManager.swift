import Foundation
import CryptoKit
import Security

enum BackupSecurityManager {
    enum Error: LocalizedError {
        case keyGeneration
        case missingBackup
        case missingKey
        case encryption
        case decryption
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keyGeneration:
                return "Nem sikerült a titkosítási kulcsot előállítani."
            case .missingBackup:
                return "Nincs visszaállítható titkosított mentés."
            case .missingKey:
                return "A titkosítási kulcs nem található a készüléken."
            case .encryption:
                return "A titkosított mentést nem sikerült létrehozni."
            case .decryption:
                return "A titkosított mentés visszafejtése nem sikerült."
            case .keychain(let status):
                return "A kulcs mentése nem sikerült (\(status))."
            }
        }
    }

    private static let service = "hu.halasz.portfolio.encrypted-backup"
    private static let keyAccount = "portfolio-aes-key-v1"
    private static let version = 1
    private static let enabledKey = "portfolioEncryptedBackupEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func hasEncryptedBackup() -> Bool {
        guard let url = PortfolioFile.encryptedBackupURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func save(_ payload: PortfolioFile.Payload) throws {
        guard isEnabled, let url = PortfolioFile.encryptedBackupURL else { return }
        let key = try currentKey()

        let raw = try JSONEncoder().encode(payload)
        guard let sealed = try? AES.GCM.seal(raw, using: key),
              let encrypted = sealed.combined else {
            throw Error.encryption
        }

        let envelope = Envelope(
            version: version,
            createdAt: Date(),
            encryptedPayload: encrypted
        )
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: url, options: .atomic)
    }

    static func load() -> PortfolioFile.Payload? {
        guard let url = PortfolioFile.encryptedBackupURL,
              FileManager.default.fileExists(atPath: url.path),
              let savedData = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: savedData)
        else { return nil }

        do {
            let key = try currentKey()
            let sealed = try AES.GCM.SealedBox(combined: envelope.encryptedPayload)
            let raw = try AES.GCM.open(sealed, using: key)
            return try JSONDecoder().decode(PortfolioFile.Payload.self, from: raw)
        } catch {
            return nil
        }
    }

    static func clearBackupFile() {
        guard let url = PortfolioFile.encryptedBackupURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func clearStoredKey() {
        SecItemDelete(baseQuery(account: keyAccount) as CFDictionary)
    }

    private struct Envelope: Codable {
        let version: Int
        let createdAt: Date
        let encryptedPayload: Data
    }

    private static func currentKey() throws -> SymmetricKey {
        if let data = try existingKey() {
            return SymmetricKey(data: data)
        }
        return try generateAndStoreKey()
    }

    private static func existingKey() throws -> Data? {
        var query = baseQuery(account: keyAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw Error.keychain(status)
        }
        return data
    }

    private static func generateAndStoreKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try save(data: data, account: keyAccount)
        return key
    }

    private static func save(data: Data, account: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Error.keychain(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
