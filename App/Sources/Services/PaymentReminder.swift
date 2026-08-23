import Foundation
import UserNotifications

/// Helyi értesítés a hitelkártya fizetési határidejéről.
///
/// **Három nappal előtte, reggel 9-kor.** Nem a határidő napján: akkor már
/// késő elindítani egy átutalást, ami napokat is futhat.
///
/// Helyi értesítés, nem szerveres: az app nem küld semmit sehova, az iOS
/// tárolja az időzítést. Engedélyt csak akkor kérünk, amikor a kapcsolót
/// bekapcsolod — indításkor engedélyt kérni azelőtt, hogy tudnád, mire jó,
/// udvariatlan és a legtöbben elutasítják.
enum PaymentReminder {

    static let identifier = "credit-card-due"
    private static let defaultsKey = "paymentReminderOn"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Engedélyt kér, és igazzal tér vissza, ha megkaptuk.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Beállítja (vagy törli) az emlékeztetőt a kártya adataiból.
    static func schedule(for status: CreditCardStatus?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard isEnabled, let status, let due = status.dueDate,
              let fireDate = Calendar.current.date(byAdding: .day, value: -3, to: due)
        else { return }

        // Múltbeli határidőre nem időzítünk: az nem sürgős, hanem elavult.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = 9
        guard let fire = Calendar.current.date(from: components), fire > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Hitelkártya fizetési határidő"
        let amount = status.minimumPayment.map { "Minimum \(Fmt.huf($0)), " } ?? ""
        content.body = "\(amount)teljes tartozás \(Fmt.huf(status.totalDebt)). Határidő: \(Fmt.day(due))."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour], from: fire),
            repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier,
                                                    content: content, trigger: trigger))
    }
}
