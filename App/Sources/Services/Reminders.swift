import Foundation
import UserNotifications

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
