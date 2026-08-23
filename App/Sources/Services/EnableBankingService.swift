import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class EnableBankingService {
    var applicationID: String
    var redirectURL: String
    var banks: [EBASPSP] = []
    var selectedBankID: String
    var applicationName: String?
    var applicationIsActive = false
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
    }

    init(defaults: UserDefaults = .standard) {
        applicationID = defaults.string(forKey: Key.applicationID) ?? ""
        redirectURL = defaults.string(forKey: Key.redirectURL) ?? ""
        selectedBankID = defaults.string(forKey: Key.selectedBankID) ?? ""
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

    var summary: String {
        guard isConnected else {
            return isConfigured ? "Beállítva, még nincs kapcsolódva" : "Nincs beállítva"
        }
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
            applicationIsActive = application.active
            guard application.active else {
                throw EnableBankingError.callback("Az Enable Banking alkalmazás még inaktív. A Control Panelen az „Activate by linking accounts” lépést kell befejezni.")
            }
            if let redirect = validRedirectURL,
               !application.redirectURLs.contains(redirect.absoluteString) {
                throw EnableBankingError.callback("A callback cím nincs az Enable Banking alkalmazás engedélyezett címei között.")
            }
            statusMessage = "Az Enable Banking alkalmazás aktív és elérhető."
        }
    }

    func loadBanks() async {
        await run {
            try persistConfiguration()
            let loaded = try await client().banks()
            banks = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if selectedBank == nil, let otp = otpBank(in: loaded) {
                selectedBankID = otp.id
                UserDefaults.standard.set(otp.id, forKey: Key.selectedBankID)
            }
            statusMessage = "\(loaded.count) magyar bank elérhető."
        }
    }

    func connect(store: PortfolioStore) async {
        await run {
            try persistConfiguration()
            let available = banks.isEmpty ? try await client().banks() : banks
            if banks.isEmpty { banks = available }
            guard let bank = selectedBank ?? otpBank(in: available) else {
                throw EnableBankingError.noOTPBank
            }
            selectedBankID = bank.id
            UserDefaults.standard.set(bank.id, forKey: Key.selectedBankID)

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
        await run { try await syncNow(store: store) }
    }

    /// A teljes engedélyezett előzmény behozása. KÜLÖN gomb, mert a bank
    /// ilyenkor megerősítést kér — az OTP SMS-ben, laponként. Egyszer
    /// érdemes lefuttatni, aztán soha többé.
    func fetchFullHistory(store: PortfolioStore) async {
        await run { try await syncNow(store: store, fullHistory: true) }
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
        get { AutoSync(rawValue: UserDefaults.standard.string(forKey: "enableBanking.autoSync")
                       ?? AutoSync.daily.rawValue) ?? .daily }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "enableBanking.autoSync") }
    }

    func syncIfStale(store: PortfolioStore) async {
        guard isConfigured, !connections.isEmpty, !isWorking else { return }
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
        applicationIsActive = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Key.applicationID)
        defaults.removeObject(forKey: Key.redirectURL)
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
        UserDefaults.standard.set(applicationID, forKey: Key.applicationID)
        UserDefaults.standard.set(redirectURL, forKey: Key.redirectURL)
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
                store.applyEnableBanking(EBSyncResult(bankName: session.aspsp.name,
                                                      accounts: synced, syncedAt: now))
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
        let defaults = UserDefaults.standard
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
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Key.connections)
        defaults.removeObject(forKey: Key.sessionID)
        defaults.removeObject(forKey: Key.bankName)
        defaults.removeObject(forKey: Key.accountCount)
        defaults.removeObject(forKey: Key.lastSync)
    }

    private func otpBank(in banks: [EBASPSP]) -> EBASPSP? {
        banks.first {
            let name = $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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


