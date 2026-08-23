import SwiftUI
import UniformTypeIdentifiers

struct BankConnectionView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(EnableBankingService.self) private var banking
    @State private var importingKey = false
    @State private var confirmDelete = false
    @State private var confirmFullHistory = false

    var body: some View {
        @Bindable var banking = banking

        List {
            Section {
                LabeledContent("Állapot", value: banking.summary)
                if let lastSync = banking.lastSync {
                    LabeledContent("Utolsó frissítés", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                }
                if banking.isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Dolgozom…")
                    }
                }
                if let message = banking.statusMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(DS.meta)
                        .foregroundStyle(.green)
                }
                if let error = banking.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(DS.meta)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Bankkapcsolat")
            }

            Section {
                TextField("Application ID", text: $banking.applicationID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("HTTPS callback cím", text: $banking.redirectURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Button {
                    importingKey = true
                } label: {
                    Label(
                        banking.hasPrivateKey ? "Privát kulcs cseréje" : ".pem privát kulcs importálása",
                        systemImage: banking.hasPrivateKey ? "checkmark.shield.fill" : "key.fill"
                    )
                }

                Button {
                    Task { await banking.saveAndCheckConfiguration() }
                } label: {
                    Label("Beállítás ellenőrzése", systemImage: "checkmark.circle")
                }
                .disabled(banking.isWorking || !banking.hasPrivateKey)
            } header: {
                Text("Enable Banking alkalmazás")
            } footer: {
                Text("A privát kulcs csak a telefon Keychainjében marad. Nem kerül a portfóliófájlba és nem szinkronizálódik iCloudon.")
            }

            Section {
                if !banking.banks.isEmpty {
                    Picker("Bank", selection: $banking.selectedBankID) {
                        ForEach(banking.banks) { bank in
                            Text(bank.name).tag(bank.id)
                        }
                    }
                } else {
                    Button {
                        Task { await banking.loadBanks() }
                    } label: {
                        Label("Magyar banklista betöltése", systemImage: "building.columns")
                    }
                    .disabled(banking.isWorking || !banking.isConfigured)
                }

                // Az összekötött bankok egyenként. Több bank kell: a
                // folyószámláid két intézménynél vannak.
                ForEach(banking.connections) { connection in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(connection.bankName).font(DS.rowTitle)
                            Spacer()
                            Text("\(connection.accountCount) számla")
                                .font(DS.meta).foregroundStyle(DS.Color.inkSoft(0.5))
                        }
                        if let until = connection.validUntil {
                            let days = Calendar.current.dateComponents(
                                [.day], from: Date(), to: until).day ?? 0
                            // A hozzájárulás lejár; ezt előre kiírjuk, hogy ne
                            // egy hibaüzenetből tudd meg.
                            Text(days > 0
                                 ? "Az engedély \(days) nap múlva jár le"
                                 : "Az engedély lejárt — kösd össze újra")
                                .font(DS.meta)
                                .foregroundStyle(days > 14 ? DS.Color.inkSoft(0.45)
                                                           : DS.Color.negativeCream)
                        }
                    }
                    .swipeActions {
                        Button("Leválasztás", role: .destructive) {
                            Task { await banking.disconnect(connection) }
                        }
                    }
                }

                Button {
                    Task { await banking.connect(store: store) }
                } label: {
                    Label(banking.isConnected ? "Másik bank hozzáadása" : "Bank összekapcsolása",
                          systemImage: "link")
                }
                .disabled(banking.isWorking || !banking.isConfigured)

                if banking.isConnected {
                    Button {
                        Task { await banking.sync(store: store) }
                    } label: {
                        Label("Számlák frissítése", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(banking.isWorking)

                    Picker("Automatikus frissítés", selection: Binding(
                        get: { banking.autoSync },
                        set: { banking.autoSync = $0 }
                    )) {
                        ForEach(EnableBankingService.AutoSync.allCases) {
                            Text($0.title).tag($0)
                        }
                    }

                    Button {
                        confirmFullHistory = true
                    } label: {
                        Label("Teljes előzmény letöltése", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(banking.isWorking)
                }
                NavigationLink {
                    BankConsentInfoView()
                } label: {
                    Label("Ha lejár az engedély", systemImage: "clock.badge.questionmark")
                }
            } header: {
                Text("Számlák")
            } footer: {
                Text("Bankonként külön jóváhagyás kell. Előbb az Enable Banking vezérlőpultján engedélyezd a bankot („Activate by linking accounts”), utána itt kösd össze — a bank jóváhagyó oldala az appon belül nyílik meg. Jóváhagyás után az egyenlegek és az elmúlt egy év tranzakciói bekerülnek. A megtakarítási és hitelkártya-számlák nem PSD2-hatályúak, azok továbbra is kivonatból jönnek.")
            }

            if banking.hasPrivateKey || !banking.applicationID.isEmpty {
                Section {
                    Button("Minden Enable Banking adat törlése", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.Color.canvas)
        .foregroundStyle(DS.Color.ink)
        .sheet(item: $banking.pendingAuth) { pending in
            BankAuthSheet(url: pending.url,
                          redirectPrefix: pending.redirectPrefix,
                          bankName: pending.bankName) { result in
                banking.finishAuthentication(result)
            }
        }
        .confirmationDialog("Teljes előzmény letöltése",
                            isPresented: $confirmFullHistory, titleVisibility: .visible) {
            Button("Letöltés") { Task { await banking.fetchFullHistory(store: store) } }
            Button("Mégse", role: .cancel) { }
        } message: {
            Text("Egy évre visszamenőleg kéri le a tételeket. A jogszabály 90 napnál régebbi előzményhez megerősítést ír elő, ezért a bank ilyenkor SMS-t küld — az OTP laponként külön üzenetet. Egyszer érdemes lefuttatni.")
        }
        .navigationTitle("Bankkapcsolat")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importingKey, allowedContentTypes: [.data, .plainText]) { result in
            switch result {
            case .failure(let error):
                banking.lastError = error.localizedDescription
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    try banking.importPrivateKey(Data(contentsOf: url))
                } catch {
                    banking.lastError = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "Törlöd a bankkapcsolat minden adatát?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Törlés", role: .destructive) { banking.deleteCredentials() }
            Button("Mégse", role: .cancel) {}
        } message: {
            Text("A privát kulcs és a kapcsolat törlődik erről a telefonról. A már beolvasott portfólióadatok megmaradnak.")
        }
        .task {
            if banking.isConfigured && banking.banks.isEmpty {
                await banking.loadBanks()
            }
        }
    }
}
