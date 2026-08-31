import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class EnableBankingService {
    /// Az Enable Banking nem kötelező az app használatához: a kivonat-import
    /// önállóan is teljes értékű marad. Ez a státusz azt teszi egyértelművé,
    /// hogy a felhasználónak mi a következő konkrét teendője.
    enum ConfigurationStatus: Hashable {
        case missingApplicationID
        case missingRedirectURL
        case missingPrivateKey
        case needsVerification
        case providerInactive
        case ready
        case connected
        case reauthorizationRequired

        var title: String {
            switch self {
            case .missingApplicationID: "Application ID hiányzik"
            case .missingRedirectURL: "HTTPS callback hiányzik"
            case .missingPrivateKey: "Privát kulcs hiányzik"
            case .needsVerification: "Ellenőrzés szükséges"
            case .providerInactive: "Szolgáltatói aktiválás szükséges"
            case .ready: "Kapcsolódásra kész"
            case .connected: "Kapcsolódva"
            case .reauthorizationRequired: "Újraengedélyezés szükséges"
            }
        }

        var systemImage: String {
            switch self {
            case .missingApplicationID, .missingRedirectURL, .missingPrivateKey:
                "exclamationmark.circle"
            case .needsVerification, .providerInactive:
                "checkmark.shield"
            case .ready:
                "checkmark.circle"
            case .connected:
                "checkmark.shield.fill"
            case .reauthorizationRequired:
                "clock.badge.exclamationmark"
            }
        }

        var detail: String {
            switch self {
            case .missingApplicationID:
                "Az Enable Banking Control Panelből származó Application ID szükséges."
            case .missingRedirectURL:
                "HTTPS callback címet adj meg, amely pontosan szerepel a provider alkalmazásában."
            case .missingPrivateKey:
                "Importáld a provider által kiadott RSA .pem kulcsot; ez csak ezen a készüléken marad."
            case .needsVerification:
                "A mezők megadása után ellenőrizd az alkalmazást, mielőtt banki adatot kérnénk le."
            case .providerInactive:
                "A provider alkalmazása inaktív. A Control Panelen fejezd be az „Activate by linking accounts” lépést."
            case .ready:
                "A provider aktív; most már kiválaszthatsz egy magyar bankot és elindíthatod a jóváhagyást."
            case .connected:
                "Az egyenlegek és a tranzakciók read-only módon, a jóváhagyott banki kapcsolaton érkeznek."
            case .reauthorizationRequired:
                "Legalább egy banki hozzájárulás lejárt. Újra kell engedélyezni; a korábbi adatok nem vesznek el."
            }
        }

        var tint: StatusTint {
            switch self {
            case .missingApplicationID, .missingRedirectURL, .missingPrivateKey,
                 .needsVerification, .providerInactive, .reauthorizationRequired:
                .attention
            case .ready, .connected:
                .positive
            }
        }
    }

    enum StatusTint { case attention, positive }

    @ObservationIgnored private let defaults: UserDefaults
    var applicationID: String
    var redirectURL: String
    var banks: [EBASPSP] = []
    var selectedBankID: String
    var applicationName: String?
    var applicationEnvironment: String?
    var applicationIsActive = false
    private(set) var configurationVerifiedAt: Date?
    private(set) var verifiedConfigurationKey: String?
    var isWorking = false
    var statusMessage: String?
    var lastError: String?

    /// Az összekötött bankok. **Több bank kell**: a folyószámláid két
    /// intézménynél vannak, és egyetlen munkamenet tárolása azt jelentette
    /// volna, hogy a második összekötés némán felülírja az elsőt.
    private(set) var connections: [EBConnection] = []
    private(set) var lastSync: Date?

    /// Egy bank élő kapcsolata.
    struct EBConnection: Codable, Identifiable, Hashable {
        var id: String { sessionID }
        var sessionID: String
        var bankID: String
        var bankName: String
        var accountCount: Int
        /// Meddig él a banki hozzájárulás. Ezt kiírjuk, mert PSD2 alatt
        /// legfeljebb ~180 nap, és utána újra be kell engedni.
        var validUntil: Date?
        var lastSync: Date?
    }

    /// A banki jóváhagyó ablak, amíg nyitva van. A nézet ebből tudja, hogy
    /// meg kell jelenítenie a lapot; a folytatást a `finishAuthentication`
    /// hívja vissza.
    var pendingAuth: PendingAuth?

    struct PendingAuth: Identifiable {
        let id = UUID()
        let url: URL
        let redirectPrefix: String
        let bankName: String
    }

    @ObservationIgnored private var authContinuation: CheckedContinuation<URL, Error>?

    private enum Key {
        static let applicationID = "enableBanking.applicationID"
        static let redirectURL = "enableBanking.redirectURL"
        static let sessionID = "enableBanking.sessionID"
        static let connections = "enableBanking.connections"
        static let bankName = "enableBanking.bankName"
        static let selectedBankID = "enableBanking.selectedBankID"
        static let accountCount = "enableBanking.accountCount"
        static let lastSync = "enableBanking.lastSync"
        static let applicationName = "enableBanking.applicationName"
        static let applicationEnvironment = "enableBanking.applicationEnvironment"
        static let applicationIsActive = "enableBanking.applicationIsActive"
        static let configurationVerifiedAt = "enableBanking.configurationVerifiedAt"
        static let verifiedConfigurationKey = "enableBanking.verifiedConfigurationKey"
        static let autoSync = "enableBanking.autoSync"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        applicationID = defaults.string(forKey: Key.applicationID) ?? ""
        redirectURL = defaults.string(forKey: Key.redirectURL) ?? ""
        selectedBankID = defaults.string(forKey: Key.selectedBankID) ?? ""
        applicationName = defaults.string(forKey: Key.applicationName)
        applicationEnvironment = defaults.string(forKey: Key.applicationEnvironment)
        applicationIsActive = defaults.bool(forKey: Key.applicationIsActive)
        let verificationTimestamp = defaults.double(forKey: Key.configurationVerifiedAt)
        configurationVerifiedAt = verificationTimestamp > 0
            ? Date(timeIntervalSince1970: verificationTimestamp) : nil
        verifiedConfigurationKey = defaults.string(forKey: Key.verifiedConfigurationKey)
        if let data = defaults.data(forKey: Key.connections),
           let stored = try? JSONDecoder().decode([EBConnection].self, from: data) {
            connections = stored
        } else if let legacy = defaults.string(forKey: Key.sessionID) {
            // Átmenet a korábbi, egyetlen munkamenetet tároló alakról.
            connections = [EBConnection(sessionID: legacy,
                                        bankID: defaults.string(forKey: Key.selectedBankID) ?? "",
                                        bankName: defaults.string(forKey: Key.bankName) ?? "Bank",
                                        accountCount: defaults.integer(forKey: Key.accountCount))]
        }
        let timestamp = defaults.double(forKey: Key.lastSync)
        lastSync = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    var hasPrivateKey: Bool { EnableBankingVault.hasPrivateKey }
    var isConfigured: Bool {
        !applicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validRedirectURL != nil && hasPrivateKey
    }
    var isConnected: Bool { !connections.isEmpty }
    /// Csak a sikeresen ellenőrzött, aktív provider-alkalmazás indíthat élő
    /// API-hívást. A pusztán kitöltött mezők nem elegendők.
    private var canUseProvider: Bool {
        switch configurationStatus {
        case .ready, .connected, .reauthorizationRequired: true
        default: false
        }
    }

    private var configurationKey: String {
        [applicationID, redirectURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
    }

    var configurationStatus: ConfigurationStatus {
        if applicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingApplicationID
        }
        guard validRedirectURL != nil else { return .missingRedirectURL }
        guard hasPrivateKey else { return .missingPrivateKey }
        guard verifiedConfigurationKey == configurationKey,
              configurationVerifiedAt != nil else { return .needsVerification }
        guard applicationIsActive else { return .providerInactive }
        if isConnected {
            let hasExpired = connections.contains {
                guard let until = $0.validUntil else { return false }
                return until <= Date()
            }
            return hasExpired ? .reauthorizationRequired : .connected
        }
        return .ready
    }

    var summary: String {
        if configurationStatus == .reauthorizationRequired {
            return "Újraengedélyezés szükséges"
        }
        guard isConnected else { return configurationStatus.title }
        let accounts = connections.reduce(0) { $0 + $1.accountCount }
        let banks = connections.count == 1 ? connections[0].bankName : "\(connections.count) bank"
        return "\(banks) · \(accounts) számla"
    }

    /// A leghamarabb lejáró hozzájárulás — ezt jelezzük előre.
    var nextExpiry: (bank: String, days: Int)? {
        let upcoming = connections.compactMap { connection -> (String, Int)? in
            guard let until = connection.validUntil,
                  let days = Calendar.current.dateComponents(
                    [.day], from: Date(), to: until).day else { return nil }
            return (connection.bankName, days)
        }
        return upcoming.min { $0.1 < $1.1 }
    }

    func importPrivateKey(_ data: Data) throws {
        try EnableBankingVault.savePrivateKey(data)
        lastError = nil
        statusMessage = "A privát kulcs biztonságosan a telefon Keychainjébe került."
    }

    func saveAndCheckConfiguration() async {
        await run {
            try persistConfiguration()
            let application = try await client().application()
            applicationName = application.name
            applicationEnvironment = application.environment
            applicationIsActive = application.active
            persistConfigurationCheck()
            guard application.active else {
                configurationVerifiedAt = nil
                verifiedConfigurationKey = nil
                persistConfigurationCheck()
                throw EnableBankingError.callback("Az Enable Banking alkalmazás még inaktív. A Control Panelen az „Activate by linking accounts” lépést kell befejezni.")
            }
            if let redirect = validRedirectURL,
               !application.redirectURLs.contains(redirect.absoluteString) {
                configurationVerifiedAt = nil
                verifiedConfigurationKey = nil
                persistConfigurationCheck()
                throw EnableBankingError.callback("A callback cím nincs az Enable Banking alkalmazás engedélyezett címei között.")
            }
            configurationVerifiedAt = Date()
            verifiedConfigurationKey = configurationKey
            persistConfigurationCheck()
            statusMessage = "Az Enable Banking alkalmazás aktív és elérhető."
        }
    }

    func loadBanks() async {
        await run {
            try persistConfiguration()
            guard canUseProvider else { throw EnableBankingError.configurationNotVerified }
            let loaded = try await client().banks()
            banks = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if selectedBank == nil, let otp = otpBank(in: loaded) {
                selectedBankID = otp.id
                defaults.set(otp.id, forKey: Key.selectedBankID)
            }
            statusMessage = "\(loaded.count) magyar bank elérhető."
        }
    }

    func connect(store: PortfolioStore) async {
        await run {
            try persistConfiguration()
            guard canUseProvider else { throw EnableBankingError.configurationNotVerified }
            let available = banks.isEmpty ? try await client().banks() : banks
            if banks.isEmpty { banks = available }
            guard let bank = selectedBank ?? otpBank(in: available) else {
                throw EnableBankingError.noOTPBank
            }
            selectedBankID = bank.id
            defaults.set(bank.id, forKey: Key.selectedBankID)

            let state = Self.secureState()
            let validUntil = EnableBankingClient.consentValidUntil(for: bank)
            let started = try await client().startAuthorization(
                bank: bank,
                redirectURL: validRedirectURL!.absoluteString,
                state: state
            )
            statusMessage = "Banki jóváhagyás folyamatban…"
            let callback = try await authenticate(at: started.url, bankName: bank.name)
            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
            let values = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            if let error = values["error"] {
                throw EnableBankingError.callback(values["error_description"] ?? error)
            }
            guard values["state"] == state else { throw EnableBankingError.stateMismatch }
            guard let code = values["code"], !code.isEmpty else { throw EnableBankingError.invalidResponse }

            let authorized = try await client().authorize(code: code)
            // HOZZÁADJUK a listához. Ha ugyanezt a bankot kötöd újra össze
            // (pl. lejárt a hozzájárulás), a régi bejegyzés cserélődik —
            // két bejegyzés ugyanarra a bankra kétszer számolná a számláit.
            connections.removeAll { $0.bankID == bank.id }
            connections.append(EBConnection(sessionID: authorized.sessionID,
                                            bankID: bank.id,
                                            bankName: authorized.aspsp.name,
                                            accountCount: authorized.accounts.count,
                                            validUntil: validUntil))
            persistConnections()
            statusMessage = "\(authorized.aspsp.name) kapcsolódva. Szinkron fut…"
            try await syncNow(store: store)
        }
    }

    func sync(store: PortfolioStore) async {
        await run {
            guard canUseProvider else { throw EnableBankingError.configurationNotVerified }
            try await syncNow(store: store)
        }
    }

    /// A teljes engedélyezett előzmény behozása. KÜLÖN gomb, mert a bank
    /// ilyenkor megerősítést kér — az OTP SMS-ben, laponként. Egyszer
    /// érdemes lefuttatni, aztán soha többé.
    func fetchFullHistory(store: PortfolioStore) async {
        await run {
            guard canUseProvider else { throw EnableBankingError.configurationNotVerified }
            try await syncNow(store: store, fullHistory: true)
        }
    }

    /// Automatikus frissítés — előtérbe kerüléskor és a napi háttérfeladatban.
    ///
    /// **Miért van benne várakozási idő:** a PSD2 végrehajtási rendelete a
    /// felhasználó JELENLÉTE NÉLKÜLI lekérdezést naponta NÉGY alkalomra
    /// korlátozza hozzájárulásonként. Ha minden előtérbe kerüléskor
    /// szinkronizálnánk, egy forgalmas napon ezt átlépnénk, és a bank
    /// elutasítana — nem csak a fölösleges hívásokat, hanem a következő
    /// jogosat is. A hat óra bőven belefér, és a folyószámla-egyenleg
    /// nem is változik ennél sűrűbben érdemben.
    ///
    /// Csendes: hibát nem tolunk a képernyőre, mert ezt nem te indítottad.
    /// A hiba a Bankkapcsolat oldalon így is megnézhető.
    /// Milyen sűrűn frissítsen magától. A választás nálad van: a bank
    /// minden adatlekérésről értesíthet, és az sokaknak zavaró.
    enum AutoSync: String, CaseIterable, Identifiable {
        case off, daily, sixHourly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off:       "Kikapcsolva"
            case .daily:     "Naponta"
            case .sixHourly: "6 óránként"
            }
        }
        var interval: TimeInterval? {
            switch self {
            case .off:       nil
            case .daily:     24 * 3600
            case .sixHourly: 6 * 3600
            }
        }
    }

    var autoSync: AutoSync {
        get { AutoSync(rawValue: defaults.string(forKey: Key.autoSync)
                       ?? AutoSync.daily.rawValue) ?? .daily }
        set { defaults.set(newValue.rawValue, forKey: Key.autoSync) }
    }

    func syncIfStale(store: PortfolioStore) async {
        guard canUseProvider, !connections.isEmpty, !isWorking else { return }
        guard let interval = autoSync.interval else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < interval { return }
        // Lejárt engedélyű bankot nem hívunk fölöslegesen: a `syncNow`
        // úgyis kihagyja, de így a hálózati kör is elmarad.
        guard connections.contains(where: { ($0.validUntil ?? .distantFuture) > Date() })
        else { return }
        await run { try await syncNow(store: store) }
    }

    /// Egy bank leválasztása.
    func disconnect(_ connection: EBConnection) async {
        await run {
            if isConfigured { try? await client().closeSession(id: connection.sessionID) }
            connections.removeAll { $0.id == connection.id }
            persistConnections()
            statusMessage = "\(connection.bankName) leválasztva."
        }
    }

    /// Minden bank leválasztása.
    func disconnect() async {
        await run {
            for connection in connections where isConfigured {
                try? await client().closeSession(id: connection.sessionID)
            }
            clearSession()
            statusMessage = "A bankkapcsolatok megszüntetve."
        }
    }

    func deleteCredentials() {
        clearSession()
        EnableBankingVault.deletePrivateKey()
        applicationID = ""
        redirectURL = ""
        applicationName = nil
        applicationEnvironment = nil
        applicationIsActive = false
        configurationVerifiedAt = nil
        verifiedConfigurationKey = nil
        defaults.removeObject(forKey: Key.applicationID)
        defaults.removeObject(forKey: Key.redirectURL)
        defaults.removeObject(forKey: Key.applicationName)
        defaults.removeObject(forKey: Key.applicationEnvironment)
        defaults.removeObject(forKey: Key.applicationIsActive)
        defaults.removeObject(forKey: Key.configurationVerifiedAt)
        defaults.removeObject(forKey: Key.verifiedConfigurationKey)
        statusMessage = "Az Enable Banking adatok törölve."
        lastError = nil
    }

    private var selectedBank: EBASPSP? { banks.first { $0.id == selectedBankID } }

    private var validRedirectURL: URL? {
        guard let url = URL(string: redirectURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    private func persistConfiguration() throws {
        applicationID = applicationID.trimmingCharacters(in: .whitespacesAndNewlines)
        redirectURL = redirectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !applicationID.isEmpty else { throw EnableBankingError.missingConfiguration }
        guard validRedirectURL != nil else { throw EnableBankingError.invalidRedirectURL }
        guard hasPrivateKey else { throw EnableBankingError.missingPrivateKey }
        defaults.set(applicationID, forKey: Key.applicationID)
        defaults.set(redirectURL, forKey: Key.redirectURL)
    }

    private func client() throws -> EnableBankingClient {
        let key = try EnableBankingVault.privateKey()
        return EnableBankingClient(applicationID: applicationID, privateKeyPEM: key)
    }

    /// Meddig kérjük vissza a tranzakciókat ennél a kapcsolatnál.
    ///
    /// **A 90 nap nem önkény.** A PSD2 végrehajtási rendelete csak az elmúlt
    /// 90 nap előzményét engedi erős ügyfél-azonosítás NÉLKÜL. Ennél
    /// régebbit kérve a bank azonosítást ír elő — az OTP ezt SMS-ben teszi
    /// („PSD2 számlatörténet megerősítése”). Mi minden szinkronnál 370 napot
    /// kértünk, tehát minden frissítés SMS-t váltott ki.
    ///
    /// **90 napnál régebbit CSAK kifejezett kérésre kérünk.** Mérve: 72 SMS
    /// jött egyetlen este alatt, mert a lekérés fiókonként HÚSZ lapig
    /// lapozhat, és minden 90 napon túli lap külön megerősítést vált ki.
    /// Ezért a teljes előzmény külön, figyelmeztetett művelet lett — soha
    /// nem fut automatikusan, még az első összekötéskor sem.
    private func transactionWindow(for connection: EBConnection,
                                   fullHistory: Bool) -> Date {
        let now = Date()
        let calendar = Calendar.current
        if fullHistory {
            return calendar.date(byAdding: .day, value: -370, to: now) ?? .distantPast
        }
        let ninety = calendar.date(byAdding: .day, value: -90, to: now) ?? .distantPast
        guard let last = connection.lastSync else { return ninety }
        // Hét nap átfedéssel: a kártyás tételek napokkal a vásárlás után
        // könyvelődnek, és a legutóbbi szinkron óta még beeshettek.
        let incremental = calendar.date(byAdding: .day, value: -7, to: last) ?? ninety
        return max(ninety, incremental)
    }

    private func syncNow(store: PortfolioStore, fullHistory: Bool = false) async throws {
        guard !connections.isEmpty else { throw EnableBankingError.noSession }
        let api = try client()
        var totalAccounts = 0
        var totalTransactions = 0
        var failures: [String] = []

        for (index, connection) in connections.enumerated() {
            do {
                let session = try await api.session(id: connection.sessionID)
                guard session.status == "AUTHORIZED" else {
                    // Az egyik bank lejárt engedélye NE akassza meg a
                    // többit: megnevezzük, és a többivel folytatjuk.
                    failures.append("\(connection.bankName): \(session.status)")
                    continue
                }
                var synced: [EBSyncResult.Account] = []
                let from = transactionWindow(for: connection, fullHistory: fullHistory)
                for accountID in session.accounts {
                    let details = try await api.account(id: accountID)
                    async let balances = api.balances(accountID: accountID)
                    async let transactions = api.transactions(accountID: accountID, from: from)
                    synced.append(try await .init(details: details, balances: balances,
                                                  transactions: transactions))
                }
                let now = Date()
                // Első összekötéskor és teljes előzmény letöltésekor a bank
                // sok régi tételt ad vissza. Az nem „most történt", ezért csak
                // egy korábban már szinkronizált kapcsolat növekményét jelezzük.
                let shouldDetectMovements = connection.lastSync != nil && !fullHistory
                let movements = store.applyEnableBanking(
                    EBSyncResult(bankName: session.aspsp.name,
                                 accounts: synced, syncedAt: now),
                    detectNewTransactions: shouldDetectMovements
                )
                await ActivityNotifications.Banking.notify(movements)
                connections[index].accountCount = synced.count
                connections[index].lastSync = now
                totalAccounts += synced.count
                totalTransactions += synced.reduce(0) { $0 + $1.transactions.count }
            } catch {
                failures.append("\(connection.bankName): \(error.localizedDescription)")
            }
        }

        lastSync = Date()
        persistConnections()
        // A lejárat-értesítést itt idozitjuk ujra: a `validUntil` csak most
        // frissult, es a lecsatolt bankok ertesitese is most tunik el.
        await Reminders.Consent.schedule(for: connections)
        var message = "Kész: \(totalAccounts) számla és \(totalTransactions) tranzakció frissült."
        if !failures.isEmpty {
            message += " Nem sikerült: \(failures.joined(separator: ", "))."
        }
        statusMessage = message
    }

    /// A banki jóváhagyás lefuttatása és a visszairányítás megvárása.
    ///
    /// **Miért nem `ASWebAuthenticationSession`:** ahhoz egyedi séma
    /// (`portfolio://`) kellene visszaútnak, az Enable Banking viszont
    /// KIZÁRÓLAG `https` címet fogad el — mérve: „URL uses unsupported
    /// scheme", majd a localhostra „invalid URL", mert éles módban külső,
    /// elérhető cím kell. A https-visszaút az `ASWebAuthenticationSession`-nél
    /// univerzális hivatkozás volna, ahhoz saját domain és társítási fájl
    /// kellene. Ezért a jóváhagyás beágyazott ablakban fut, és a
    /// visszairányítást a betöltés ELŐTT fogjuk el (`BankAuthWebView`).
    private func authenticate(at url: URL, bankName: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            authContinuation = continuation
            pendingAuth = PendingAuth(url: url,
                                      redirectPrefix: validRedirectURL!.absoluteString,
                                      bankName: bankName)
        }
    }

    /// A jóváhagyó ablak eredménye. Pontosan egyszer folytatja a várakozást.
    func finishAuthentication(_ result: Result<URL, Error>) {
        pendingAuth = nil
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume(with: result)
    }

    private func persistConnections() {
        defaults.set(try? JSONEncoder().encode(connections), forKey: Key.connections)
        defaults.set(lastSync?.timeIntervalSince1970 ?? 0, forKey: Key.lastSync)
        // A régi, egy-munkamenetes kulcsok már nem kellenek.
        defaults.removeObject(forKey: Key.sessionID)
        defaults.removeObject(forKey: Key.bankName)
        defaults.removeObject(forKey: Key.accountCount)
    }

    private func clearSession() {
        connections = []
        lastSync = nil
        defaults.removeObject(forKey: Key.connections)
        defaults.removeObject(forKey: Key.sessionID)
        defaults.removeObject(forKey: Key.bankName)
        defaults.removeObject(forKey: Key.accountCount)
        defaults.removeObject(forKey: Key.lastSync)
    }

    private func persistConfigurationCheck() {
        if let applicationName {
            defaults.set(applicationName, forKey: Key.applicationName)
        } else {
            defaults.removeObject(forKey: Key.applicationName)
        }
        if let applicationEnvironment {
            defaults.set(applicationEnvironment, forKey: Key.applicationEnvironment)
        } else {
            defaults.removeObject(forKey: Key.applicationEnvironment)
        }
        defaults.set(applicationIsActive, forKey: Key.applicationIsActive)
        defaults.set(configurationVerifiedAt?.timeIntervalSince1970 ?? 0,
                     forKey: Key.configurationVerifiedAt)
        if let verifiedConfigurationKey {
            defaults.set(verifiedConfigurationKey, forKey: Key.verifiedConfigurationKey)
        } else {
            defaults.removeObject(forKey: Key.verifiedConfigurationKey)
        }
    }

    private func otpBank(in banks: [EBASPSP]) -> EBASPSP? {
        banks.first {
            // A folding kisbetűsít, ezért nagybetűsítünk utána — ugyanaz a
            // minta, mint az `ExpenseCategorizer.normalize`. Enélkül a
            // `contains("OTP")` soha nem talált.
            let name = $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                       locale: .current).uppercased()
            return name.contains("OTP")
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do { try await operation() }
        catch { lastError = error.localizedDescription }
    }

    private static func secureState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return UUID().uuidString
    }
}
