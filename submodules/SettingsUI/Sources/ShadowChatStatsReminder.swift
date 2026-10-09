import Foundation
import UserNotifications

// Shadow: «Напоминать раз в месяц» in «Итоги чатов» (1.11.0). A local
// notification on the 1st of every month at 12:00; tapping it opens
// shadow://stats (AppDelegate opens userInfo["url"] of a notification).
// Lives on this device only (UserDefaults), like the intruder photo switches:
// it is not an AyuGramSettings field, not exported and not synced.
enum ShadowChatStatsReminder {
    static let identifier = "shadow.chatStats.monthly"
    static let url = "shadow://stats"
    private static let key = "shadow.chatStats.monthlyReminder.v1"

    static var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: key)
    }

    // Turns the reminder on or off. Turning it on asks for notification
    // permission if it was never asked; `completion(false)` — iOS does not
    // allow notifications, so the reminder stays off.
    static func setEnabled(_ enabled: Bool, completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        guard enabled else {
            UserDefaults.standard.set(false, forKey: key)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            completion(true)
            return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge], completionHandler: { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    UserDefaults.standard.set(false, forKey: key)
                    completion(false)
                    return
                }
                UserDefaults.standard.set(true, forKey: key)
                schedule()
                completion(true)
            }
        })
    }

    static func schedule() {
        let content = UNMutableNotificationContent()
        content.title = "Итоги месяца"
        content.body = "Новый месяц — посмотрите, как вы общались. Нажмите, чтобы посчитать итоги."
        content.sound = .default
        content.userInfo = ["url": url]
        var date = DateComponents()
        date.day = 1
        date.hour = 12
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger), withCompletionHandler: nil)
    }
}
