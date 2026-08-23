import Foundation
import UserNotifications

/// Előtérben is megmutatja az eseményértesítéseket. Delegált nélkül az iOS
/// csendben elnyeli a bannert, amíg az app nyitva van — épp akkor, amikor egy
/// kézi frissítés eredménye megérkezik.
final class PortfolioNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PortfolioNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Helyi értesítések, amiket az app maga időzít.
///
/// Nincs mögöttük szerver: az időzítést az iOS tárolja, az app nem küld
/// semmit sehova. Engedélyt csak akkor kérünk, amikor bekapcsolsz egyet —
/// indításkor kérni azelőtt, hogy tudnád, mire jó, udvariatlan.
///
/// Mindegyik KÜLÖN kapcsolható: aki a kártya-határidőt kéri, nem biztos,
/// hogy a havi kivonat-emlékeztetőt is akarja.
enum Reminders {

    /// Igazzal tér vissza, ha megkaptuk az engedélyt.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: - Havi kivonat-emlékeztető

    /// A bankkapcsolat a folyószámlákat magától hozza, de a megtakarítási
    /// és hitelkártya-számlák nem PSD2-hatályúak: azok CSAK kivonatból
    /// frissülnek. Ezért marad értelme a havi emlékeztetőnek akkor is,
    /// amikor már minden bank össze van kötve.
    enum Statements {
        static let identifier = "statement-import-monthly"
        private static let key = "statementReminderOn"

        /// Nem elsején: a bankok a hónap első napjaiban állítják ki a
        /// kivonatot, ilyenkor még jellemzően nincs mit letölteni.
        static let dayOfMonth = 5

        static var isEnabled: Bool {
            get { UserDefaults.standard.bool(forKey: key) }
            set { UserDefaults.standard.set(newValue, forKey: key) }
        }

        static func schedule() async {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            guard isEnabled else { return }

            let content = UNMutableNotificationContent()
            content.title = "Havi kivonatok"
            content.body = "Töltsd le a múlt havi kivonatokat, és oszd meg őket az appnak. "
                         + "A megtakarítási és a hitelkártya-számla csak innen frissül."
            content.sound = .default

            var when = DateComponents()
            when.day = dayOfMonth
            when.hour = 9
            // repeats: true — minden hónap 5-én, amíg ki nem kapcsolod.
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: identifier,
                                                        content: content, trigger: trigger))
        }
    }

    // MARK: - Banki engedély lejárata

    /// A PSD2 hozzájárulás legfeljebb 180 napig él (az OTP és a Revolut is
    /// ennyit ad — lekérdezve, nem feltételezve). Utána a frissítés hibára
    /// fut, amíg újra jóvá nem hagyod. Ezt jobb előre tudni.
    enum Consent {
        static let prefix = "bank-consent-"
        private static let key = "consentReminderOn"

        /// Egy héttel előbb: van idő nyugodtan elvégezni, de még nem olyan
        /// távoli, hogy elfelejtsd.
        static let leadDays = 7

        static var isEnabled: Bool {
            get { UserDefaults.standard.bool(forKey: key) }
            set { UserDefaults.standard.set(newValue, forKey: key) }
        }

        /// Bankonként külön értesítés, mert bankonként külön jár le.
        /// Mindig mindet újraidőzítjük: így a leválasztott bank értesítése
        /// is eltűnik, nem csak a megmaradóké frissül.
        static func schedule(for connections: [EnableBankingService.EBConnection]) async {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            guard isEnabled else { return }

            for connection in connections {
                guard let until = connection.validUntil,
                      let fireDay = Calendar.current.date(byAdding: .day,
                                                          value: -leadDays, to: until)
                else { continue }

                var components = Calendar.current.dateComponents(
                    [.year, .month, .day], from: fireDay)
                components.hour = 9
                // Múltbeli időpontra nem időzítünk: az nem figyelmeztetés,
                // hanem elavult adat. A lejáratot a Bankkapcsolat oldal
                // amúgy is kiírja.
                guard let fire = Calendar.current.date(from: components), fire > Date()
                else { continue }

                let content = UNMutableNotificationContent()
                content.title = "\(connection.bankName): lejár az engedély"
                content.body = "\(leadDays) nap múlva lejár a banki hozzájárulás. "
                             + "Kösd össze újra a Beállításokban — egy perc, és adat nem vész el."
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour], from: fire),
                    repeats: false)
                try? await center.add(UNNotificationRequest(
                    identifier: prefix + connection.sessionID,
                    content: content, trigger: trigger))
            }
        }
    }
}

// MARK: - Eseményvezérelt értesítések

/// Az időzített emlékeztetőkkel szemben ezek akkor születnek, amikor egy
/// frissítés valódi, jelentős változást talál. Nincs push-szerver: az app az
/// iOS által adott előtér- vagy háttér-frissítési alkalommal ellenőriz.
enum ActivityNotifications {
    private static func hasAuthorization() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Napon belül ugyanarra az instrumentumra és irányra csak egyszer
    /// szólunk. Az árfolyamforrás egy frissítés közben többször is előkerülhet
    /// (közvetlen pozíció, híroldali komponens), ez nem két esemény.
    private static func shouldSend(key: String, storageKey: String,
                                   now: Date = Date()) -> Bool {
        let defaults = UserDefaults.standard
        var sent = defaults.dictionary(forKey: storageKey)?.compactMapValues {
            ($0 as? NSNumber)?.doubleValue
        } ?? [:]
        let cutoff = now.addingTimeInterval(-3 * 24 * 3600).timeIntervalSince1970
        sent = sent.filter { $0.value >= cutoff }
        guard sent[key] == nil else {
            defaults.set(sent, forKey: storageKey)
            return false
        }
        sent[key] = now.timeIntervalSince1970
        defaults.set(sent, forKey: storageKey)
        return true
    }

    private static func safeKey(_ value: String) -> String {
        value.lowercased().unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "-"
        }.joined()
    }

    private static func price(_ value: Decimal, currency: String) -> String {
        switch currency.uppercased() {
        case "HUF": Fmt.huf(value)
        case "EUR": Fmt.eur(value)
        default: "\(Fmt.decimal(value, min: 2, max: 2)) \(currency.uppercased())"
        }
    }

    enum Market {
        struct Move: Sendable {
            let id: String
            let name: String
            let symbol: String
            let changePct: Double
            let price: Decimal
            let currency: String
        }

        static let thresholdPct = 3.0
        private static let enabledKey = "marketMovementNotificationsOn"
        private static let sentKey = "marketMovementNotificationsSent"

        static var isEnabled: Bool {
            get { UserDefaults.standard.bool(forKey: enabledKey) }
            set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
        }

        static func notify(_ moves: [Move]) async {
            guard isEnabled, await hasAuthorization() else { return }
            let day = ConstituentWatcher.dayKey(Date())
            let significant = moves.filter { abs($0.changePct) >= thresholdPct }
                .sorted { abs($0.changePct) > abs($1.changePct) }
                .prefix(6)

            for move in significant {
                guard !Task.isCancelled else { return }
                let direction = move.changePct >= 0 ? "up" : "down"
                let key = "\(day)|\(safeKey(move.id))|\(direction)"
                guard shouldSend(key: key, storageKey: sentKey) else { continue }

                let content = UNMutableNotificationContent()
                content.title = move.changePct >= 0
                    ? "\(move.symbol) jelentősen emelkedik"
                    : "\(move.symbol) jelentősen esik"
                content.body = "\(move.name): \(Fmt.percent(move.changePct)) ma · "
                    + "most \(price(move.price, currency: move.currency))."
                content.sound = .default
                content.interruptionLevel = .active
                content.userInfo = ["kind": "market", "instrument": move.id]

                let request = UNNotificationRequest(
                    identifier: "market-\(day)-\(safeKey(move.id))-\(direction)",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                )
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }

    enum Banking {
        struct Movement: Sendable {
            let id: String
            let account: String
            let merchant: String
            let amountHUF: Decimal
        }

        static let thresholdHUF: Decimal = 25_000
        private static let enabledKey = "bankMovementNotificationsOn"
        private static let sentKey = "bankMovementNotificationsSent"

        static var isEnabled: Bool {
            get { UserDefaults.standard.bool(forKey: enabledKey) }
            set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
        }

        static func notify(_ movements: [Movement]) async {
            guard isEnabled, await hasAuthorization() else { return }
            let significant = movements.filter { abs($0.amountHUF) >= thresholdHUF }
                .sorted { abs($0.amountHUF) > abs($1.amountHUF) }
                .prefix(8)

            for movement in significant {
                guard !Task.isCancelled else { return }
                let key = safeKey(movement.id)
                guard shouldSend(key: key, storageKey: sentKey) else { continue }

                let incoming = movement.amountHUF > 0
                let content = UNMutableNotificationContent()
                content.title = incoming ? "Jóváírás érkezett" : "Nagyobb terhelés történt"
                content.body = "\(incoming ? "+" : "−")\(Fmt.huf(abs(movement.amountHUF))) · "
                    + "\(movement.merchant) · \(movement.account)"
                content.sound = .default
                content.interruptionLevel = .active
                content.userInfo = ["kind": "bank", "transaction": movement.id]

                let request = UNNotificationRequest(
                    identifier: "bank-\(key)",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                )
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }
}
