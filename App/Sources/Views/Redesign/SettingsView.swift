import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(EnableBankingService.self) private var banking
    @Environment(\.dismiss) private var dismiss
    var showsDone: Bool = false

    @State private var isImporting = false
    @State private var notice: Notice?
    @State private var editingAsset: CashAsset?
    @State private var isAddingAsset = false
    @State private var isAddingHolding = false
    @State private var encryptedBackupEnabled = BackupSecurityManager.isEnabled

    private struct Notice: Identifiable {
        let id = UUID(); let title: String; let message: String
    }

    @State private var pickingFolder = false
    @State private var watchedFolderNames: [String] = WatchedFolders.urls.map(\.lastPathComponent)
    // A kapcsolók a UserDefaults-ból indulnak, de nézet-állapotként élnek:
    // ha az engedélyt megtagadod, vissza kell tudni billenteni őket.
    @State private var cardReminder = PaymentReminder.isEnabled
    @State private var statementReminder = Reminders.Statements.isEnabled
    @State private var consentReminder = Reminders.Consent.isEnabled
    @State private var notificationsDenied = false
    /// A törlés visszavonhatatlan és tranzakciókat is elvisz, ezért kérdezünk.
    @State private var deletingPlatform: Platform?

    var body: some View {
        NavigationStack {
            List {
                Section("Bankkapcsolat") {
                    NavigationLink {
                        BankConnectionView()
                    } label: {
                        Label("Enable Banking", systemImage: "building.columns")
                    }
                }

                Section {
                    Toggle("Hitelkártya fizetési határidő", isOn: Binding(
                        get: { cardReminder },
                        set: { on in
                            cardReminder = on
                            Task {
                                if on, await Reminders.requestPermission() == false {
                                    cardReminder = false; PaymentReminder.isEnabled = false
                                    notificationsDenied = true; return
                                }
                                PaymentReminder.isEnabled = on
                                await PaymentReminder.schedule(for: store.creditCards.first)
                            }
                        }
                    ))
                    Toggle("Havi kivonat-emlékeztető", isOn: Binding(
                        get: { statementReminder },
                        set: { on in
                            statementReminder = on
                            Task {
                                if on, await Reminders.requestPermission() == false {
                                    statementReminder = false; Reminders.Statements.isEnabled = false
                                    notificationsDenied = true; return
                                }
                                Reminders.Statements.isEnabled = on
                                await Reminders.Statements.schedule()
                            }
                        }
                    ))
                    Toggle("Banki engedély lejárata", isOn: Binding(
                        get: { consentReminder },
                        set: { on in
                            consentReminder = on
                            Task {
                                if on, await Reminders.requestPermission() == false {
                                    consentReminder = false; Reminders.Consent.isEnabled = false
                                    notificationsDenied = true; return
                                }
                                Reminders.Consent.isEnabled = on
                                await Reminders.Consent.schedule(for: banking.connections)
                            }
                        }
                    ))
                } header: {
                    Text("Értesítések")
                } footer: {
                    Text("Helyi értesítések: az időzítést az iOS tárolja, az app nem küld semmit sehova. A kártya-határidőről három nappal előbb, a kivonatokról minden hónap \(Reminders.Statements.dayOfMonth)-én, a banki engedély lejáratáról \(Reminders.Consent.leadDays) nappal előbb szólok — mindegyik reggel 9-kor.")
                }

                Section("Adatok") {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Kivonat beolvasása", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await store.backfill() }
                    } label: {
                        Label("Görbe visszatöltése", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(store.holdings.isEmpty)
                }

                Section("Fejlesztői eszközök") {
                    NavigationLink {
                        AllocationPlannerView()
                    } label: {
                        Label("Célallokáció és új pénz elosztása", systemImage: "target")
                    }
                    NavigationLink {
                        MaturityCalendarView()
                    } label: {
                        Label("Kamat- és lejárati naptár", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        DataFreshnessCenterView()
                    } label: {
                        Label("Adatfrissességi központ", systemImage: "tray.full")
                    }
                } footer: {
                    Text("Ezek a nézetek a teljes vagyon, a termékesemények és az adatok állapotát mutatják.")
                }

                Section("Titkosított biztonsági mentés") {
                    Toggle("Engedélyezés", isOn: Binding(
                        get: { encryptedBackupEnabled },
                        set: { enabled in
                            encryptedBackupEnabled = enabled
                            BackupSecurityManager.isEnabled = enabled
                            if enabled {
                                store.save()
                                notice = Notice(
                                    title: "Titkosított mentés engedélyezve",
                                    message: "A következő mentéstől az adatok titkosított másolatként is mentésre kerülnek."
                                )
                            } else {
                                BackupSecurityManager.clearBackupFile()
                                notice = Notice(
                                    title: "Titkosított mentés letiltva",
                                    message: "Az utolsó titkosított mentés fájlát töröltük, a kapcsoló kikapcsolt állapotban."
                                )
                            }
                        }
                    ))

                    if BackupSecurityManager.hasEncryptedBackup() {
                        Button {
                            BackupSecurityManager.clearBackupFile()
                            notice = Notice(
                                title: "Titkosított mentés törölve",
                                message: "A biztonsági másolat törölve lett."
                            )
                        } label: {
                            Label("Titkosított mentés törlése", systemImage: "trash")
                                .foregroundStyle(DS.Color.negativeCream)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("A mentés helyileg marad, és felhasználói jelszó nélkül visszatölthető egy megerősített készüléken.")
                }

                Section {
                    ForEach(store.cashAssets) { asset in
                        Button { editingAsset = asset } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.name).font(DS.rowTitle)
                                    Text(assetMeta(asset))
                                        .font(DS.meta)
                                        .foregroundStyle(DS.Color.inkSoft(0.5))
                                }
                                Spacer()
                                Text(Fmt.huf(store.convertToHUF(asset.estimatedBalance(),
                                                                currency: asset.currency)))
                                    .font(DS.font(13.5, .medium))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        isAddingAsset = true
                    } label: {
                        Label("Megtakarítási számla felvétele", systemImage: "plus")
                    }
                    Button {
                        isAddingHolding = true
                    } label: {
                        Label("Értékpapír kézzel", systemImage: "plus")
                    }
                } header: {
                    Text("Kamatozó megtakarítás")
                } footer: {
                    Text("A Revolut megtakarítási kivonatából automatikusan bekerül, a napi kamattal együtt. Kézzel csak akkor kell felvenni, ha olyan számlád van, amiről nincs beolvasható kivonat.")
                }

                Section {
                    ForEach(Array(watchedFolderNames.enumerated()), id: \.offset) { index, name in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(DS.Color.coral)
                            Text(name).font(DS.rowTitle)
                            Spacer()
                        }
                        .swipeActions {
                            Button("Törlés", role: .destructive) {
                                WatchedFolders.remove(at: index)
                                watchedFolderNames = WatchedFolders.urls.map(\.lastPathComponent)
                            }
                        }
                    }
                    Button {
                        pickingFolder = true
                    } label: {
                        Label("Mappa kijelölése", systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text("Figyelt mappák")
                } footer: {
                    Text("Kijelölhetsz mappákat — akár az iCloud Drive-ban —, és az app minden megnyitáskor átnézi őket. Csak a felismerhető nevű kivonat-fájlokhoz nyúl (OTP, Revolut, Lightyear, Államkincstár); a fájljaid a helyükön maradnak.")
                }

                if !store.resolvedPlatforms.isEmpty {
                    Section {
                        ForEach(store.resolvedPlatforms) { platform in
                            NavigationLink(platform.name) {
                                PlatformEditor(platform: platform)
                            }
                            .swipeActions {
                                Button("Törlés", role: .destructive) {
                                    deletingPlatform = platform
                                }
                            }
                        }
                        .onMove { store.movePlatforms(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        HStack {
                            Text("Platformok")
                            Spacer()
                            EditButton().font(DS.meta).textCase(nil)
                        }
                    } footer: {
                        Text("A „Szerkesztés” után a jobb oldali fogantyúval rendezheted át a kártyákat — a kezdőképernyő ezt a sorrendet követi. Amíg nem nyúlsz hozzá, érték szerint csökkenő a sorrend, és az új számla a lista végére kerül.\n\nHúzd balra a törléshez: az a számlát és a tételeit is elviszi, de a kivonat és a bankkapcsolat érintetlen marad, tehát a következő frissítés visszahozhatja.")
                    }
                }

                Section {
                    Toggle("Az ikon kövesse a témát", isOn: Binding(
                        get: { store.iconFollowsTheme },
                        set: { store.iconFollowsTheme = $0 }
                    ))
                    .font(DS.rowTitle)
                } footer: {
                    Text("Minden témához tartozik egy app-ikon, ugyanabból a színpárból. Az iOS ilyenkor felugró értesítést mutat az ikoncseréről — ez a rendszer sajátja, nem lehet elnyomni, ezért van külön kapcsolóban.")
                }

                Section {
                    ForEach(AppTheme.darkShelled) { themeRow($0) }
                } header: {
                    Text("Színtéma · sötét részletlapok")
                } footer: {
                    Text("A vászon világos módban világos, sötétben sötét — az app a rendszert követi. A platform-részletek viszont ezeknél a témáknál mindkét módban sötétek. Minden témának SAJÁT harmónia-sémája van (komplementer, triád, analóg, tetrád), más vezető árnyalattal — ezért nem hasonlítanak egymásra.")
                }

                Section {
                    ForEach(AppTheme.lightShelled) { themeRow($0) }
                } header: {
                    Text("Világos részletlapok")
                } footer: {
                    Text("Ezeknél világos módban a platform-részletek is világosak — fehér vagy halványan árnyalt alapon, sötét szöveggel. A három akcentus mindenhol azonos érzékelt világosságú, hogy a kártyák egymás mellett kiegyensúlyozottak legyenek, a rajtuk lévő szöveg színe pedig mért kontraszt szerint dől el. A nyereség zöld, a veszteség piros marad minden témában — azok nem akcentusok.")
                }

                Section("Árfolyamforrás") {
                    LabeledContent("EUR/HUF", value: Fmt.decimal(store.fxRate, max: 2))
                    if let date = store.fxDate {
                        LabeledContent("Jegyzés", value: "\(store.fxSource) · \(Fmt.day(date))")
                    }
                    let spreads = Set(store.conversionSpread.values.filter { $0 > 0 })
                    if spreads.count == 1, let spread = spreads.first {
                        LabeledContent("Átváltási árrés",
                                       value: String(format: "%.2f%%", spread.doubleValue * 100))
                    }
                }
            }
            .fileImporter(isPresented: $pickingFolder,
                          allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    WatchedFolders.add(url)
                    watchedFolderNames = WatchedFolders.urls.map(\.lastPathComponent)
                    // Azonnal át is nézzük — ne kelljen újraindítani.
                    Task { await store.startup() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(DS.Color.canvas)
            .foregroundStyle(DS.Color.ink)
            .navigationTitle("Beállítások")
            .confirmationDialog(
                deletingPlatform.map { "\($0.name) törlése" } ?? "Törlés",
                isPresented: Binding(get: { deletingPlatform != nil },
                                     set: { if !$0 { deletingPlatform = nil } }),
                titleVisibility: .visible
            ) {
                Button("Törlés", role: .destructive) {
                    if let platform = deletingPlatform { store.removeAccount(platform.id) }
                    deletingPlatform = nil
                }
                Button("Mégse", role: .cancel) { deletingPlatform = nil }
            } message: {
                Text("Az egyenlege, a tranzakciói és a befizetései is törlődnek. A kivonatok és a bankkapcsolat érintetlen marad, tehát a következő frissítés visszahozhatja.")
            }
            .alert("Az értesítések ki vannak kapcsolva", isPresented: $notificationsDenied) {
                Button("Beállítások megnyitása") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Mégse", role: .cancel) { }
            } message: {
                Text("Az iOS-ben engedélyezned kell az értesítéseket a Portfóliónak, különben ezek a kapcsolók nem tudnak működni.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kész") { dismiss() }
                    }
                }
            }
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                Task { await handleImport(result) }
            }
            .sheet(item: $editingAsset) { CashAssetEditor(asset: $0) }
            .sheet(isPresented: $isAddingAsset) { CashAssetEditor(asset: nil) }
            .sheet(isPresented: $isAddingHolding) { HoldingEditorView(holding: nil) }
            .alert(item: $notice) { n in
                Alert(title: Text(n.title), message: Text(n.message),
                      dismissButton: .default(Text("Rendben")))
            }
        }
        .tint(DS.Color.coral)
    }

    /// A kamat és az, hogy melyik napi kivonatból való — így látszik, hogy a
    /// szám részben becslés, nem tiszta mérés.
    private func assetMeta(_ asset: CashAsset) -> String {
        var parts: [String] = []
        if let rate = asset.netDailyRate {
            parts.append(String(format: "%.2f%% nettó", rate.doubleValue * 365 * 100))
        }
        let days = asset.daysSinceStatement()
        if days > 0, asset.netDailyRate != nil {
            parts.append("+\(Fmt.huf(asset.estimatedInterest())) becsülve")
        } else if let asOf = asset.asOf {
            parts.append("\(Fmt.day(asOf))")
        }
        if parts.isEmpty { parts.append(asset.currency) }
        return parts.joined(separator: " · ")
    }

    private func handleImport(_ result: Result<URL, Error>) async {
        switch result {
        case .failure(let error):
            notice = Notice(title: "Nem sikerült", message: error.localizedDescription)
        case .success(let url):
            do {
                let year = Calendar.current.component(.year, from: Date())
                let (warnings, account) = try await store.importStatement(from: url, tbszYear: year)
                var message = "Számla: \(account)\n\(store.holdings.count) pozíció, \(store.deposits.count) befizetés."
                if !warnings.isEmpty {
                    message += "\n\n" + Set(warnings).sorted().joined(separator: "\n")
                }
                notice = Notice(title: "Beolvasva", message: message)
            } catch {
                notice = Notice(title: "Nem sikerült", message: error.localizedDescription)
            }
        }
    }
}


extension SettingsView {
    /// Egy témasor. Két szekció használja, ezért külön — a különbség csak az,
    /// melyik listából jön a téma.
    @ViewBuilder func themeRow(_ theme: AppTheme) -> some View {
        Button { store.setTheme(theme) } label: {
            HStack(spacing: 12) {
                ThemeSwatch(theme: theme)
                Text(theme.name).font(DS.rowTitle)
                Spacer()
                if theme.id == store.themeID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Color.coral)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Egy téma előnézete: vászon, héj és a három akcentus.
struct ThemeSwatch: View {
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: theme.canvasLight))
                .frame(width: 12, height: 26)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: theme.cardLight))
                .frame(width: 8, height: 26)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: theme.shellDeepLight))
                .frame(width: 12, height: 26)
            VStack(spacing: 2) {
                ForEach(theme.accents, id: \.self) { hex in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: hex))
                        .frame(width: 16, height: 7)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(DS.Color.inkSoft(0.12)))
    }
}

/// Kamatozó megtakarítás szerkesztése.
struct CashAssetEditor: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let existing: CashAsset?
    @State private var name: String
    @State private var balance: String
    @State private var currency: String
    @State private var rate: String

    init(asset: CashAsset?) {
        existing = asset
        _name = State(initialValue: asset?.name ?? "Revolut Savings")
        _balance = State(initialValue: asset.map { Fmt.decimal($0.balance, max: 2) } ?? "")
        _currency = State(initialValue: asset?.currency ?? "HUF")
        _rate = State(initialValue: asset?.annualRatePct.map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Számla") {
                    LabeledContent("Név") {
                        TextField("Revolut Savings", text: $name).multilineTextAlignment(.trailing)
                    }
                    Picker("Deviza", selection: $currency) {
                        ForEach(["HUF", "EUR", "USD"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    LabeledContent("Egyenleg") {
                        TextField("0", text: $balance)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Éves kamat (%)") {
                        TextField("nem kötelező", text: $rate)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("A kamat csak tájékoztató adat — az app nem számol vele előre, csak azt mutatja, amit beírtál.")
                }
                if let existing {
                    Section {
                        Button("Törlés", role: .destructive) {
                            store.deleteCashAsset(existing); dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Új megtakarítás" : "Megtakarítás")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Mégse") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kész") { commit() }.disabled(parsedBalance == nil)
                }
            }
        }
    }

    private var parsedBalance: Decimal? {
        let normalized = balance.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func commit() {
        guard let value = parsedBalance else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var asset = existing ?? CashAsset(
            platform: "savings-" + UUID().uuidString.prefix(8),
            name: trimmed, balance: 0, currency: currency
        )
        asset.name = trimmed.isEmpty ? "Megtakarítás" : trimmed
        asset.balance = value
        asset.currency = currency
        asset.annualRatePct = Double(rate.replacingOccurrences(of: ",", with: "."))
        store.upsertCashAsset(asset)
        dismiss()
    }
}

/// Platform átnevezése és színének megválasztása.
struct PlatformEditor: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Platform

    init(platform: Platform) { _draft = State(initialValue: platform) }

    var body: some View {
        Form {
            Section("Megjelenés") {
                LabeledContent("Név") {
                    TextField("Név", text: $draft.name).multilineTextAlignment(.trailing)
                }
                LabeledContent("Monogram") {
                    TextField("VW", text: $draft.monogram)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Szín", selection: $draft.accent) {
                    Text("Korall").tag(Platform.Accent.coral)
                    Text("Menta").tag(Platform.Accent.mint)
                    Text("Lila").tag(Platform.Accent.lilac)
                }
            }
            Section {
                LabeledContent("Azonosító", value: draft.id)
                if let year = draft.tbszYear {
                    LabeledContent("TBSZ gyűjtőév", value: String(year))
                }
            }
        }
        .navigationTitle("Platform")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.upsertPlatform(draft) }
    }
}
