import Foundation
import SwiftUI
import SwiftData
import UserNotifications

enum Keys {
    static let overallBudget = "overallBudget"
    static let notifyOnCapture = "notifyOnCapture"
    static let lastBackup = "lastBackup"
    static let setupSeen = "setupSeen"
}

// MARK: - Formatting

private let groupedFormatters: [Int: NumberFormatter] = {
    var d: [Int: NumberFormatter] = [:]
    for n in 0...2 {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = n
        f.maximumFractionDigits = n
        d[n] = f
    }
    return d
}()

func num(_ v: Double, _ decimals: Int = 0) -> String {
    groupedFormatters[decimals]?.string(from: NSNumber(value: v)) ?? String(format: "%.\(decimals)f", v)
}
func rm(_ v: Double) -> String { "RM " + num(v, 2) }
func rm0(_ v: Double) -> String { "RM " + num(v, 0) }

enum Fmt {
    static let dateTime: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
    static let time: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short; return f
    }()
    static let dayHeader: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, d MMM"; return f
    }()
    static let month: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()
    static let shortMonth: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    static let fileStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmm"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    static let csv: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}

extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
    var endOfMonth: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: startOfMonth) ?? self
    }
    func sameMonth(_ other: Date) -> Bool { Calendar.current.isDate(self, equalTo: other, toGranularity: .month) }
}

// MARK: - Notifications

/// Opens a payment for editing when a capture notification is tapped.
final class Router: ObservableObject {
    static let shared = Router()
    @Published var openTxn: UUID?
    @Published var openReview = false
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["txn"] as? String, let id = UUID(uuidString: s) {
            await MainActor.run { Router.shared.openTxn = id }
        }
    }
}

enum Notify {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func message(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    static func captured(_ t: Txn) {
        guard UserDefaults.standard.object(forKey: Keys.notifyOnCapture) as? Bool ?? true else { return }
        let c = UNMutableNotificationContent()
        if t.needsReview {
            c.title = "Check this payment"
            c.body = t.amount > 0 ? "\(rm(t.amount)) · \(t.displayName) — tap to confirm the details." : "Couldn't read the amount — tap to fill it in."
        } else {
            c.title = "\(rm(t.amount)) · \(t.displayName)"
            c.body = "Saved as \(t.category) (\(t.method.title))" + (t.possibleDuplicate ? " — possible duplicate." : ". Tap to change.")
        }
        c.sound = .default
        c.userInfo = ["txn": t.id.uuidString]
        let req = UNNotificationRequest(identifier: t.id.uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
