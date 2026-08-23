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
    @State private var marketAlerts = ActivityNotifications.Market.isEnabled
    @State private var bankAlerts = ActivityNotifications.Banking.isEnabled
    @State private var notificationsDenied = false
    /// A törlés visszavonhatatlan és tranzakciókat is elvisz, ezért kérdezünk.
    @State private var deletingPlatform: Platform?

    var body: some View {
        NavigationStack {
            List {
                themesSection

                bankSection
                legalSection

                notificationSection

                dataSection

                developerToolsSection

                backupSection

                cashAssetsSection

                watchedFoldersSection

                platformsSection

                fxSection
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
                deletingPlatformTitle,
                isPresented: deletingPlatformIsPresented,
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
                          allowedContentTypes: [.pdf, .commaSeparatedText, .plainText, .text]) { result in
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
    private func updateStatementReminder(_ enabled: Bool) {
        statementReminder = enabled
        Task { @MainActor in
            if enabled, await Reminders.requestPermission() == false {
                statementReminder = false
                Reminders.Statements.isEnabled = false
                notificationsDenied = true
                return
            }
            Reminders.Statements.isEnabled = enabled
            await Reminders.Statements.schedule()
        }
    }

    @ViewBuilder
    private var notificationSection: some View {
        Section {
            Toggle("Hitelkártya fizetési határidő", isOn: Binding(
                get: { cardReminder },
                set: { updateCardReminder($0) }
            ))
            Toggle("Havi kivonat-emlékeztető", isOn: Binding(
                get: { statementReminder },
                set: { updateStatementReminder($0) }
            ))
            Toggle("Banki engedély lejárata", isOn: Binding(
                get: { consentReminder },
                set: { updateConsentReminder($0) }
            ))
            Toggle("Jelentős árfolyammozgás", isOn: Binding(
                get: { marketAlerts },
                set: { updateMarketAlerts($0) }
            ))
            Toggle("Banki pénzmozgás", isOn: Binding(
                get: { bankAlerts },
                set: { updateBankAlerts($0) }
            ))
        } header: {
            Text("Értesítések")
        } footer: {
            Text(verbatim: notificationFooter)
        }
    }

    @ViewBuilder
    private var bankSection: some View {
        Section {
            NavigationLink {
                BankConnectionView()
            } label: {
                Label("Enable Banking", systemImage: "building.columns")
            }
        } header: {
            Text("Bankkapcsolat")
        }
    }

    @ViewBuilder
    private var legalSection: some View {
        Section {
            NavigationLink {
                LegalDocumentView(document: .privacy)
            } label: {
                Label("Adatkezelés", systemImage: "lock.shield")
            }
            NavigationLink {
                LegalDocumentView(document: .terms)
            } label: {
                Label("Felhasználási feltételek", systemImage: "doc.text")
            }
        } header: {
            Text("Jogi")
        }
    }

    private func updateCardReminder(_ enabled: Bool) {
        cardReminder = enabled
        Task { @MainActor in
            if enabled, await Reminders.requestPermission() == false {
                cardReminder = false
                PaymentReminder.isEnabled = false
                notificationsDenied = true
                return
            }
            PaymentReminder.isEnabled = enabled
            let creditCard = store.creditCards.first
            await PaymentReminder.schedule(for: creditCard)
        }
    }

    private func updateConsentReminder(_ enabled: Bool) {
        consentReminder = enabled
        Task { @MainActor in
            if enabled, await Reminders.requestPermission() == false {
                consentReminder = false
                Reminders.Consent.isEnabled = false
                notificationsDenied = true
                return
            }
            Reminders.Consent.isEnabled = enabled
            let connections = banking.connections
            await Reminders.Consent.schedule(for: connections)
        }
    }

    private func updateMarketAlerts(_ enabled: Bool) {
        marketAlerts = enabled
        Task { @MainActor in
            if enabled, await Reminders.requestPermission() == false {
                marketAlerts = false
                ActivityNotifications.Market.isEnabled = false
                notificationsDenied = true
                return
            }
            ActivityNotifications.Market.isEnabled = enabled
        }
    }

    private func updateBankAlerts(_ enabled: Bool) {
        bankAlerts = enabled
        Task { @MainActor in
            if enabled, await Reminders.requestPermission() == false {
                bankAlerts = false
                ActivityNotifications.Banking.isEnabled = false
                notificationsDenied = true
                return
            }
            ActivityNotifications.Banking.isEnabled = enabled
        }
    }

    private var notificationFooter: String {
        let statementDay = Reminders.Statements.dayOfMonth
        let consentLeadDays = Reminders.Consent.leadDays
        return "Helyi értesítések: az app nem küld pénzügyi adatot sehova. "
            + "A mozgásjelzés ±\(Fmt.percentPlain(ActivityNotifications.Market.thresholdPct, digits: 0)), "
            + "a banki küszöb \(Fmt.huf(ActivityNotifications.Banking.thresholdHUF)). "
            + "Ezek frissítéskor szólnak; a banki gyakoriságot a Bankkapcsolatnál állíthatod. "
            + "Az emlékeztetők: kártya −3 nap, kivonat minden hónap \(statementDay)-én, "
            + "engedély −\(consentLeadDays) nap, reggel 9-kor."
    }

    private var deletingPlatformTitle: String {
        guard let deletingPlatform else { return "Törlés" }
        return deletingPlatform.name + " törlése"
    }

    private var deletingPlatformIsPresented: Binding<Bool> {
        Binding(
            get: { deletingPlatform != nil },
            set: { if !$0 { deletingPlatform = nil } }
        )
    }

    @ViewBuilder
    private var developerToolsSection: some View {
        Section {
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
        } header: {
            Text("Fejlesztői eszközök")
        } footer: {
            Text("Ezek a nézetek a teljes vagyon, a termékesemények és az adatok állapotát mutatják.")
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section {
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
        } header: {
            Text("Adatok")
        }
    }

    @ViewBuilder
    private var backupSection: some View {
        Section {
            Toggle("Engedélyezés", isOn: Binding(
                get: { encryptedBackupEnabled },
                set: updateEncryptedBackup
            ))

            if BackupSecurityManager.hasEncryptedBackup() {
                Button {
                    BackupSecurityManager.clearBackupFile()
                    notice = Notice(title: "Titkosított mentés törölve",
                                    message: "A biztonsági másolat törölve lett.")
                } label: {
                    Label("Titkosított mentés törlése", systemImage: "trash")
                        .foregroundStyle(DS.Color.negativeCream)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Titkosított biztonsági mentés")
        } footer: {
            Text("A mentés helyileg marad, és felhasználói jelszó nélkül visszatölthető egy megerősített készüléken.")
        }
    }

    @ViewBuilder
    private var cashAssetsSection: some View {
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
                        Text(Fmt.huf(store.convertToHUF(asset.estimatedBalance(), currency: asset.currency)))
                            .font(DS.font(13.5, .medium))
                    }
                }
                .buttonStyle(.plain)
            }
            Button { isAddingAsset = true } label: {
                Label("Megtakarítási számla felvétele", systemImage: "plus")
            }
            Button { isAddingHolding = true } label: {
                Label("Értékpapír kézzel", systemImage: "plus")
            }
        } header: {
            Text("Kamatozó megtakarítás")
        } footer: {
            Text("A Revolut megtakarítási kivonatából automatikusan bekerül, a napi kamattal együtt. Kézzel csak akkor kell felvenni, ha olyan számlád van, amiről nincs beolvasható kivonat.")
        }
    }

    @ViewBuilder
    private var watchedFoldersSection: some View {
        Section {
            ForEach(Array(watchedFolderNames.enumerated()), id: \.offset) { index, name in
                HStack {
                    Image(systemName: "folder").foregroundStyle(DS.Color.coral)
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
            Button { pickingFolder = true } label: {
                Label("Mappa kijelölése", systemImage: "folder.badge.plus")
            }
        } header: {
            Text("Figyelt mappák")
        } footer: {
            Text("Kijelölhetsz mappákat — akár az iCloud Drive-ban —, és az app minden megnyitáskor átnézi őket. Csak a felismerhető nevű kivonat-fájlokhoz nyúl (OTP, Revolut, Lightyear, Államkincstár); a fájljaid a helyükön maradnak.")
        }
    }

    @ViewBuilder
    private var platformsSection: some View {
        if !store.resolvedPlatforms.isEmpty {
            Section {
                ForEach(store.resolvedPlatforms) { platform in
                    NavigationLink(platform.name) {
                        PlatformEditor(platform: platform)
                    }
                    .swipeActions {
                        Button("Törlés", role: .destructive) { deletingPlatform = platform }
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
    }

    @ViewBuilder
    private var themesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Megjelenés")
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.inkSoft(0.62))

                Picker("Megjelenés", selection: Binding(
                    get: { store.appearanceMode },
                    set: { store.setAppearanceMode($0) }
                )) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            ThemeGallery(
                title: "Világos paletták",
                subtitle: "napfényes változat",
                themes: AppTheme.all,
                selectedID: store.themeID,
                isDark: false,
                onSelect: store.setTheme
            )

            ThemeGallery(
                title: "Sötét párok",
                subtitle: "ugyanazok a színek, mély tónuson",
                themes: AppTheme.all,
                selectedID: store.themeID,
                isDark: true,
                onSelect: store.setTheme
            )

            Toggle("Az ikon kövesse a témát", isOn: Binding(
                get: { store.iconFollowsTheme },
                set: { store.iconFollowsTheme = $0 }
            ))
            .font(DS.rowTitle)
        } header: {
            Text("Témák")
        } footer: {
            Text("A színpaletta és a fényerő egymástól független. A Rendszer mód a telefon beállítását követi; a másik kettő rögzíti az app megjelenését. Az app-ikon cseréjekor az iOS saját értesítést jelenít meg.")
        }
    }

    @ViewBuilder
    private var fxSection: some View {
        Section {
            LabeledContent("EUR/HUF", value: Fmt.decimal(store.fxRate, max: 2))
            if let date = store.fxDate {
                LabeledContent("Jegyzés", value: store.fxSource + " · " + Fmt.day(date))
            }
            let spreads = Set(store.conversionSpread.values.filter { $0 > 0 })
            if spreads.count == 1, let spread = spreads.first {
                LabeledContent("Átváltási árrés", value: String(format: "%.2f%%", spread.doubleValue * 100))
            }
        } header: {
            Text("Árfolyamforrás")
        }
    }

    private func updateEncryptedBackup(_ enabled: Bool) {
        encryptedBackupEnabled = enabled
        BackupSecurityManager.isEnabled = enabled
        if enabled {
            store.save()
            notice = Notice(title: "Titkosított mentés engedélyezve",
                            message: "A következő mentéstől az adatok titkosított másolatként is mentésre kerülnek.")
        } else {
            BackupSecurityManager.clearBackupFile()
            notice = Notice(title: "Titkosított mentés letiltva",
                            message: "Az utolsó titkosított mentés fájlát töröltük, a kapcsoló kikapcsolt állapotban.")
        }
    }

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


struct ThemeGallery: View {
    let title: String
    let subtitle: String
    let themes: [AppTheme]
    let selectedID: String
    let isDark: Bool
    let onSelect: (AppTheme) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(DS.rowTitle)
                Spacer()
                Text(subtitle)
                    .font(DS.badge)
                    .foregroundStyle(DS.Color.inkSoft(0.52))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(themes) { theme in
                        ThemeGalleryCard(
                            theme: theme,
                            isDark: isDark,
                            isSelected: theme.id == selectedID
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) {
                                onSelect(theme)
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, 6)
    }
}

/// Apró, de valódi képernyőhangulatot mutató témaelőkép. A sarokban lévő
/// lágy átmenet az eredeti kártyadesign motívumát viszi tovább.
struct ThemeGalleryCard: View {
    let theme: AppTheme
    let isDark: Bool
    let isSelected: Bool
    let action: () -> Void

    private var canvas: Color { Color(hex: isDark ? theme.canvasDark : theme.canvasLight) }
    private var card: Color { Color(hex: isDark ? theme.cardDark : theme.cardLight) }
    private var ink: Color { Color(hex: isDark ? theme.inkDark : theme.inkLight) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canvas)

                    RadialGradient(
                        colors: [Color(hex: theme.accents[0]).opacity(0.42), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 88
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ink.opacity(0.72))
                                .frame(width: 34, height: 4)
                            Spacer()
                            Circle()
                                .fill(Color(hex: theme.positive))
                                .frame(width: 5, height: 5)
                        }

                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(card)
                                .overlay(alignment: .leading) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(ink.opacity(0.78))
                                            .frame(width: 32, height: 5)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color(hex: theme.accents[1]))
                                            .frame(width: 44, height: 4)
                                    }
                                    .padding(8)
                                }

                            ZStack {
                                Circle().stroke(ink.opacity(0.10), lineWidth: 7)
                                Circle()
                                    .trim(from: 0.05, to: 0.70)
                                    .stroke(Color(hex: theme.accents[0]),
                                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 31, height: 31)
                        }
                        .frame(height: 42)

                        HStack(spacing: 3) {
                            ForEach(Array(theme.accents.enumerated()), id: \.offset) { _, hex in
                                Capsule()
                                    .fill(Color(hex: hex))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 5)
                            }
                        }
                    }
                    .padding(10)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: theme.inkOnAccents[0]))
                            .frame(width: 20, height: 20)
                            .background(Color(hex: theme.accents[0]), in: Circle())
                            .padding(7)
                    }
                }
                .frame(width: 148, height: 102)

                Text(theme.name)
                    .font(DS.meta)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? DS.Color.coral.opacity(0.10) : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? DS.Color.coral : DS.Color.inkSoft(0.10),
                        lineWidth: isSelected ? 1.5 : 1)
        }
        .accessibilityLabel("\(theme.name), \(isDark ? "sötét" : "világos") téma")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
