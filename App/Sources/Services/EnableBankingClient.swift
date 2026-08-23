import Foundation
import Security

// MARK: - Enable Banking API models

struct EBASPSP: Codable, Hashable, Identifiable {
    var id: String { "\(country)|\(name)" }
    let name: String
    let country: String
    let logo: String?
    let maximumConsentValidity: Int
    let psuTypes: [String]

    enum CodingKeys: String, CodingKey {
        case name, country, logo
        case maximumConsentValidity = "maximum_consent_validity"
        case psuTypes = "psu_types"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        country = try c.decode(String.self, forKey: .country)
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        maximumConsentValidity = try c.decodeIfPresent(Int.self, forKey: .maximumConsentValidity) ?? 7_776_000
        psuTypes = try c.decodeIfPresent([String].self, forKey: .psuTypes) ?? ["personal"]
    }
}

struct EBAccount: Codable, Hashable, Identifiable {
    let uid: String?
    let accountID: EBAccountIdentification?
    let name: String?
    let details: String?
    let cashAccountType: String
    let product: String?
    let currency: String

    var id: String { uid ?? accountID?.iban ?? UUID().uuidString }
    var iban: String? { accountID?.iban }
    var displayName: String {
        if let details, !details.isEmpty { return details }
        if let product, !product.isEmpty { return product }
        if let iban, !iban.isEmpty { return "•••• \(iban.suffix(4))" }
        if let name, !name.isEmpty { return name }
        return "Bankszámla"
    }

    enum CodingKeys: String, CodingKey {
        case uid, name, details, product, currency
        case accountID = "account_id"
        case cashAccountType = "cash_account_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decodeIfPresent(String.self, forKey: .uid)
        accountID = try c.decodeIfPresent(EBAccountIdentification.self, forKey: .accountID)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        details = try c.decodeIfPresent(String.self, forKey: .details)
        cashAccountType = try c.decodeIfPresent(String.self, forKey: .cashAccountType) ?? "CACC"
        product = try c.decodeIfPresent(String.self, forKey: .product)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "HUF"
    }
}

struct EBAccountIdentification: Codable, Hashable {
    let iban: String?
}

struct EBAmount: Codable, Hashable {
    let currency: String
    private let amountText: String

    var amount: Decimal { Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }

    enum CodingKeys: String, CodingKey { case currency, amountText = "amount" }
}

struct EBBalance: Codable, Hashable {
    let name: String?
    let balanceAmount: EBAmount
    let balanceType: String?
    let lastChangeDateTime: String?
    let referenceDate: String?

    enum CodingKeys: String, CodingKey {
        case name
        case balanceAmount = "balance_amount"
        case balanceType = "balance_type"
        case lastChangeDateTime = "last_change_date_time"
        case referenceDate = "reference_date"
    }
}

struct EBParty: Codable, Hashable { let name: String? }

struct EBTransaction: Codable, Hashable {
    let entryReference: String?
    let transactionAmount: EBAmount
    let creditor: EBParty?
    let debtor: EBParty?
    let creditDebitIndicator: String
    let status: String
    let bookingDate: String?
    let valueDate: String?
    let transactionDate: String?
    let remittanceInformation: [String]
    let note: String?
    let transactionID: String?

    enum CodingKeys: String, CodingKey {
        case entryReference = "entry_reference"
        case transactionAmount = "transaction_amount"
        case creditor, debtor, status, note
        case creditDebitIndicator = "credit_debit_indicator"
        case bookingDate = "booking_date"
        case valueDate = "value_date"
        case transactionDate = "transaction_date"
        case remittanceInformation = "remittance_information"
        case transactionID = "transaction_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entryReference = try c.decodeIfPresent(String.self, forKey: .entryReference)
        transactionAmount = try c.decode(EBAmount.self, forKey: .transactionAmount)
        creditor = try c.decodeIfPresent(EBParty.self, forKey: .creditor)
        debtor = try c.decodeIfPresent(EBParty.self, forKey: .debtor)
        creditDebitIndicator = try c.decodeIfPresent(String.self, forKey: .creditDebitIndicator) ?? "DBIT"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "BOOK"
        bookingDate = try c.decodeIfPresent(String.self, forKey: .bookingDate)
        valueDate = try c.decodeIfPresent(String.self, forKey: .valueDate)
        transactionDate = try c.decodeIfPresent(String.self, forKey: .transactionDate)
        remittanceInformation = try c.decodeIfPresent([String].self, forKey: .remittanceInformation) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
        transactionID = try c.decodeIfPresent(String.self, forKey: .transactionID)
    }

    var description: String {
        let ownSide = creditDebitIndicator == "CRDT" ? debtor?.name : creditor?.name
        return ([ownSide] + remittanceInformation.map(Optional.some) + [note])
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct EBApplication: Decodable {
    let name: String
    let active: Bool
    let environment: String
    let redirectURLs: [String]

    enum CodingKeys: String, CodingKey {
        case name, active, environment
        case redirectURLs = "redirect_urls"
    }
}

struct EBAuthorizedSession: Decodable {
    let sessionID: String
    let accounts: [EBAccount]
    let aspsp: EBASPSPRef

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case accounts, aspsp
    }
}

struct EBASPSPRef: Codable, Hashable { let name: String; let country: String }

struct EBSession: Decodable {
    struct AccountRef: Decodable { let uid: String }
    let status: String
    let accounts: [String]
    let accountsData: [AccountRef]
    let aspsp: EBASPSPRef

    enum CodingKeys: String, CodingKey {
        case status, accounts, aspsp
        case accountsData = "accounts_data"
    }
}

struct EBStartAuthorizationResponse: Decodable {
    let url: URL
    let authorizationID: String

    enum CodingKeys: String, CodingKey {
        case url
        case authorizationID = "authorization_id"
    }
}

struct EBSyncResult {
    struct Account {
        let details: EBAccount
        let balances: [EBBalance]
        let transactions: [EBTransaction]
    }
    let bankName: String
    let accounts: [Account]
    let syncedAt: Date
}

// MARK: - Keychain and JWT

enum EnableBankingVault {
    private static let service = "hu.halasz.portfolio.enable-banking"
    private static let privateKeyAccount = "private-key"

    static var hasPrivateKey: Bool { (try? load(account: privateKeyAccount)) != nil }

    static func savePrivateKey(_ pem: Data) throws {
        guard let text = String(data: pem, encoding: .utf8), text.contains("PRIVATE KEY") else {
            throw EnableBankingError.invalidPrivateKey
        }
        _ = try EnableBankingJWT.privateKey(fromPEM: pem)
        try save(pem, account: privateKeyAccount)
    }

    static func privateKey() throws -> Data {
        guard let data = try load(account: privateKeyAccount) else {
            throw EnableBankingError.missingPrivateKey
        }
        return data
    }

    static func deletePrivateKey() {
        SecItemDelete(baseQuery(account: privateKeyAccount) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func save(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw EnableBankingError.keychain(status) }
    }

    private static func load(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw EnableBankingError.keychain(status)
        }
        return data
    }
}

enum EnableBankingJWT {
    static func make(applicationID: String, pem: Data, now: Date = Date()) throws -> String {
        let iat = Int(now.timeIntervalSince1970)
        let header: [String: Any] = ["alg": "RS256", "kid": applicationID, "typ": "JWT"]
        let claims: [String: Any] = [
            "aud": "api.enablebanking.com",
            "exp": iat + 600,
            "iat": iat,
            "iss": "enablebanking.com"
        ]
        let encoder: ([String: Any]) throws -> String = { object in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return data.base64URLEncodedString()
        }
        let signingInput = try "\(encoder(header)).\(encoder(claims))"
        let key = try privateKey(fromPEM: pem)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData, &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? EnableBankingError.signingFailed as CFError
        }
        return "\(signingInput).\(signature.base64URLEncodedString())"
    }

    static func privateKey(fromPEM pem: Data) throws -> SecKey {
        guard let text = String(data: pem, encoding: .utf8) else {
            throw EnableBankingError.invalidPrivateKey
        }
        let isPKCS8 = text.contains("-----BEGIN PRIVATE KEY-----")
        let body = text
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard var der = Data(base64Encoded: body), !der.isEmpty else {
            throw EnableBankingError.invalidPrivateKey
        }
        if isPKCS8 { der = try DER.unwrapPKCS8(der) }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? EnableBankingError.invalidPrivateKey as CFError
        }
        guard SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw EnableBankingError.invalidPrivateKey
        }
        return key
    }

    private enum DER {
        /// PKCS#8 burok lehántása, hogy a `SecKeyCreateWithData` PKCS#1-et kapjon.
        ///
        /// A szerkezet:
        /// ```
        /// SEQUENCE {            <- külső
        ///   INTEGER 0,          <- verzió
        ///   SEQUENCE { OID },   <- algoritmus
        ///   OCTET STRING { … }  <- maga a kulcs, PKCS#1-ben
        /// }
        /// ```
        /// **Figyelem a kurzorra:** a `readTLV` a mező VÉGE UTÁNRA lépteti a
        /// kurzort. A külső `SEQUENCE`-t tehát nem „átlépni" kell, hanem
        /// BELELÉPNI — a tartalmán új kurzort nyitva. A korábbi változat az
        /// egészet átugrotta, és utána a verziómezőt már a puffer végén
        /// kereste: minden valódi kulcs betöltése elbukott.
        static func unwrapPKCS8(_ data: Data) throws -> Data {
            var outer = Cursor(bytes: [UInt8](data))
            let contents = try outer.readTLV(expectedTag: 0x30)
            var inner = Cursor(bytes: contents)
            _ = try inner.readTLV(expectedTag: 0x02)   // verzió
            _ = try inner.readTLV(expectedTag: 0x30)   // algoritmus
            return Data(try inner.readTLV(expectedTag: 0x04))
        }

        private struct Cursor {
            let bytes: [UInt8]
            var offset = 0

            mutating func readTLV(expectedTag: UInt8) throws -> [UInt8] {
                guard offset < bytes.count, bytes[offset] == expectedTag else {
                    throw EnableBankingError.invalidPrivateKey
                }
                offset += 1
                let length = try readLength()
                guard length >= 0, offset + length <= bytes.count else {
                    throw EnableBankingError.invalidPrivateKey
                }
                let value = Array(bytes[offset ..< offset + length])
                offset += length
                return value
            }

            mutating func readLength() throws -> Int {
                guard offset < bytes.count else { throw EnableBankingError.invalidPrivateKey }
                let first = Int(bytes[offset]); offset += 1
                if first & 0x80 == 0 { return first }
                let count = first & 0x7f
                guard count > 0, count <= 4, offset + count <= bytes.count else {
                    throw EnableBankingError.invalidPrivateKey
                }
                var length = 0
                for _ in 0..<count { length = (length << 8) | Int(bytes[offset]); offset += 1 }
                return length
            }
        }
    }
}

// MARK: - HTTP client

final class EnableBankingClient: @unchecked Sendable {
    private let applicationID: String
    private let privateKeyPEM: Data
    private let baseURL = URL(string: "https://api.enablebanking.com")!
    private let session: URLSession
    /// A PSU IP-cím kikeresése hálózati hívás, ezért egy futamra megjegyezzük.
    /// Aktorban tároljuk: zárat nem használhatunk, mert async környezetben
    /// a lock/unlock Swift 6-ban már hiba, nem csak figyelmeztetés.
    private actor PSUIPCache {
        private var value: String?
        func get() -> String? { value }
        func set(_ newValue: String) { value = newValue }
    }
    private let psuIPCache = PSUIPCache()

    init(applicationID: String, privateKeyPEM: Data, session: URLSession = .shared) {
        self.applicationID = applicationID
        self.privateKeyPEM = privateKeyPEM
        self.session = session
    }

    func application() async throws -> EBApplication {
        try await request(path: "/application")
    }

    func banks(country: String = "HU") async throws -> [EBASPSP] {
        let response: BanksResponse = try await request(
            path: "/aspsps", query: [
                URLQueryItem(name: "country", value: country),
                URLQueryItem(name: "psu_type", value: "personal"),
                URLQueryItem(name: "service", value: "AIS")
            ])
        return response.aspsps
    }

    /// Meddig kérjük a hozzáférést.
    ///
    /// A felső korlát 180 nap: a PSD2 2022-es módosítása óta a
    /// számlainformációs hozzájárulás eddig élhet, és a bankok többsége
    /// ennyit is ad. A korábbi 90 napos plafon a mi oldalunkról jött —
    /// fölösleges önkorlátozás volt, kétszer annyi újra-engedélyezéssel.
    /// A tényleges értéket úgyis a BANK maximuma szabja meg.
    static func consentValidUntil(for bank: EBASPSP, now: Date = Date()) -> Date {
        let seconds = max(3_600, min(bank.maximumConsentValidity, 180 * 24 * 3_600))
        return now.addingTimeInterval(TimeInterval(seconds))
    }

    func startAuthorization(bank: EBASPSP, redirectURL: String, state: String) async throws -> EBStartAuthorizationResponse {
        let body: [String: Any] = [
            "access": [
                "balances": true,
                "transactions": true,
                "valid_until": Self.rfc3339.string(from: Self.consentValidUntil(for: bank))
            ],
            "aspsp": ["name": bank.name, "country": bank.country],
            "state": state,
            "redirect_url": redirectURL,
            "psu_type": "personal",
            "language": "hu"
        ]
        return try await request(path: "/auth", method: "POST", json: body)
    }

    func authorize(code: String) async throws -> EBAuthorizedSession {
        try await request(path: "/sessions", method: "POST", json: ["code": code])
    }

    func session(id: String) async throws -> EBSession {
        try await request(path: "/sessions/\(id)")
    }

    func account(id: String) async throws -> EBAccount {
        try await request(path: "/accounts/\(id)/details")
    }

    func balances(accountID: String) async throws -> [EBBalance] {
        let response: BalancesResponse = try await request(path: "/accounts/\(accountID)/balances")
        return response.balances
    }

    func transactions(accountID: String, from: Date, to: Date = Date()) async throws -> [EBTransaction] {
        var all: [EBTransaction] = []
        var continuation: String?
        for _ in 0..<20 {
            var query = [
                URLQueryItem(name: "date_from", value: Self.day.string(from: from)),
                URLQueryItem(name: "date_to", value: Self.day.string(from: to)),
                URLQueryItem(name: "transaction_status", value: "BOOK")
            ]
            if let continuation { query.append(URLQueryItem(name: "continuation_key", value: continuation)) }
            let page: TransactionsResponse = try await request(
                path: "/accounts/\(accountID)/transactions", query: query)
            all.append(contentsOf: page.transactions)
            guard let next = page.continuationKey, !next.isEmpty, next != continuation else { break }
            continuation = next
        }
        return all
    }

    func closeSession(id: String) async throws {
        let _: SuccessResponse = try await request(path: "/sessions/\(id)", method: "DELETE")
    }

    /// Az OTP — és az `/aspsps` válasz `required_psu_headers` mezoje szerint
    /// tobb mas bank is — kotelezoen keri a PSU (vagyis a te) IP-cimedet a
    /// `psu-ip-address` fejlecben. Enelkul a bank elutasitja az adatlekerest,
    /// es a hiba felenk csak "Error interacting with ASPSP" (400) alakban
    /// latszik: nem arulja el, mi hianyzik. A Revolut nem keri, ezert mukodott
    /// az fejlec nelkul is — vagyis a tunet bankonkent elter, az ok kozos.
    ///
    /// Kulso szolgaltatastol kerdezzuk meg, mert a keszulek csak a belso
    /// halozati cimet ismeri, a bank viszont a nyilvanosat varja. Ide
    /// SEMMILYEN banki adat nem megy: a valasz maga az IP-cim, es a kereses
    /// nem tartalmaz azonositot. Ha egyik forras sem valaszol, elhagyjuk a
    /// fejlecet — halozat nelkul ugyis minden mas hivas is elbukna.
    private static let psuIPSources = [
        "https://checkip.amazonaws.com",
        "https://api.ipify.org",
    ]

    private func psuIPAddress() async -> String? {
        if let cached = await psuIPCache.get() { return cached }

        for source in Self.psuIPSources {
            guard let url = URL(string: source),
                  let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  Self.looksLikeIPAddress(text)
            else { continue }
            await psuIPCache.set(text)
            return text
        }
        return nil
    }

    /// Szandekosan szigoru: barmit is ad vissza a kulso forras, csak akkor
    /// tesszuk fejlecbe, ha tenyleg cimnek nez ki.
    static func looksLikeIPAddress(_ text: String) -> Bool {
        if text.contains(":") {                       // IPv6
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            return parts.count >= 3 && parts.count <= 8
                && parts.allSatisfy { $0.count <= 4 && $0.allSatisfy(\.isHexDigit) }
        }
        let parts = text.split(separator: ".")        // IPv4
        return parts.count == 4 && parts.allSatisfy {
            guard let n = Int($0), (0...255).contains(n) else { return false }
            return true
        }
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        json: [String: Any]? = nil
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw EnableBankingError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let jwt = try EnableBankingJWT.make(applicationID: applicationID, pem: privateKeyPEM)
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        if let ip = await psuIPAddress() {
            request.setValue(ip, forHTTPHeaderField: "psu-ip-address")
        }
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EnableBankingError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EnableBankingError.api(status: http.statusCode, message: Self.apiMessage(data))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw EnableBankingError.decoding(error.localizedDescription) }
    }

    private static func apiMessage(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Ismeretlen API-hiba"
        }
        return (object["error_description"] as? String)
            ?? (object["message"] as? String)
            ?? (object["detail"] as? String)
            ?? (object["error"] as? String)
            ?? "Ismeretlen API-hiba"
    }

    private struct BanksResponse: Decodable { let aspsps: [EBASPSP] }
    private struct BalancesResponse: Decodable { let balances: [EBBalance] }
    private struct TransactionsResponse: Decodable {
        let transactions: [EBTransaction]
        let continuationKey: String?
        enum CodingKeys: String, CodingKey { case transactions; case continuationKey = "continuation_key" }
    }
    private struct SuccessResponse: Decodable { let message: String? }

    private static let rfc3339: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

enum EnableBankingError: LocalizedError {
    case missingConfiguration
    case missingPrivateKey
    case invalidPrivateKey
    case invalidRedirectURL
    case invalidResponse
    case stateMismatch
    case callback(String)
    case signingFailed
    case keychain(OSStatus)
    case api(status: Int, message: String)
    case decoding(String)
    case noOTPBank
    case noSession

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "Add meg az Application ID-t és a callback címet."
        case .missingPrivateKey: "Importáld az Enable Bankingtől letöltött .pem privát kulcsot."
        case .invalidPrivateKey: "Ez a fájl nem olvasható RSA privát kulcs. A regisztrációkor letöltött .pem fájlt válaszd."
        case .invalidRedirectURL: "A callback címnek https:// címmel kell kezdődnie."
        case .invalidResponse: "Az Enable Banking válasza nem értelmezhető."
        case .stateMismatch: "A banki visszatérés biztonsági ellenőrzése nem sikerült. Indítsd újra a kapcsolódást."
        case .callback(let message): message
        case .signingFailed: "Nem sikerült aláírni az Enable Banking kérést."
        case .keychain(let status): "A kulcs biztonságos mentése nem sikerült (\(status))."
        case .api(let status, let message): "Enable Banking hiba (\(status)): \(message)"
        case .decoding(let message): "Az Enable Banking új vagy váratlan adatot küldött: \(message)"
        case .noOTPBank: "Az OTP Bank Hungary nem található az Enable Banking magyar banklistájában."
        case .noSession: "Még nincs összekapcsolt bankszámla."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
