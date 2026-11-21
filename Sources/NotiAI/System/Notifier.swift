import Cocoa
import UserNotifications

/// How answers are shown.
enum AnswerStyle: String, Codable, CaseIterable {
    /// A regular macOS notification (looks like every other app's, can't be restyled).
    case notification
    /// Noti AI's own floating card, which can be see-through.
    case card
}

/// Shows answers and errors, either as macOS notifications or as the floating card.
/// Clicking either opens the full answer in a window.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()
    private let category = "ANSWER"
    private let copyAction = "COPY"
    private let toast = ToastController()
    private var keyMonitor: Any?
    private var lastToast: (q: String, a: String, s: String)?

    var style: AnswerStyle = .notification
    var cardOpacity: Double = 0.9
    /// Seconds before an answer hides itself; 0 keeps it.
    var dismissAfter: Double = 5
    /// (question, answer, source) when the user clicks an answer.
    var onOpen: ((String, String, String) -> Void)?
    /// (title, body, source) when notifications are turned off, so nothing gets lost.
    var onBlocked: ((String, String, String) -> Void)?

    func setUp() {
        center.delegate = self
        let copy = UNNotificationAction(identifier: copyAction, title: "Copy answer")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [copy], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        toast.onClick = { [weak self] in
            if let t = self?.lastToast { self?.onOpen?(t.q, t.a, t.s) }
        }
    }

    /// Applies the answer-related settings.
    func configure(_ c: Config) {
        style = c.answerStyle
        cardOpacity = c.cardOpacity
        dismissAfter = c.dismissAfter
        setDismissOnKey(c.dismissOnKey)
    }

    /// Whether macOS currently lets us show notifications.
    func isAllowed(_ done: @escaping (Bool) -> Void) {
        center.getNotificationSettings { s in
            done([.authorized, .provisional].contains(s.authorizationStatus))
        }
    }

    func answer(_ answer: String, question: String, source: String) {
        if style == .card {
            DispatchQueue.main.async {
                self.lastToast = (question, answer, source)
                self.toast.show(title: question, message: answer, isError: false,
                                opacity: self.cardOpacity, hideAfter: self.dismissAfter)
            }
            return
        }
        post(title: preview(question), body: answer,
             info: ["q": question, "a": answer, "s": source], actionable: true)
    }

    func error(_ message: String) {
        if style == .card {
            DispatchQueue.main.async {
                self.lastToast = nil
                self.toast.show(title: "Noti AI", message: message, isError: true,
                                opacity: self.cardOpacity, hideAfter: max(self.dismissAfter, 6))
            }
            return
        }
        post(title: "Noti AI", body: message, info: [:], actionable: false)
    }

    /// Clears every answer Noti AI is showing.
    func dismissAll() {
        center.removeAllDeliveredNotifications()
        DispatchQueue.main.async { self.toast.hide() }
    }

    // MARK: - Dismiss on key press

    /// Watches key presses in other apps (allowed because Noti AI has Accessibility access).
    private func setDismissOnKey(_ on: Bool) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        guard on else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Ignore the ⌘C Noti AI itself sends to copy your selection.
            if event.modifierFlags.contains(.command) && event.keyCode == 8 { return }
            self?.dismissAll()
        }
    }

    // MARK: - System notifications

    private func post(title: String, body: String, info: [String: String], actionable: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = info
        if actionable { content.categoryIdentifier = category }
        // `add` reports success even when notifications are off, so check first.
        isAllowed { ok in
            guard ok else {
                DispatchQueue.main.async { self.onBlocked?(info["q"] ?? title, body, info["s"] ?? "") }
                return
            }
            let id = UUID().uuidString
            self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            if self.dismissAfter > 0 {
                // Removing a delivered notification takes it off screen and out of Notification Center.
                DispatchQueue.main.asyncAfter(deadline: .now() + self.dismissAfter) {
                    self.center.removeDeliveredNotifications(withIdentifiers: [id])
                }
            }
        }
    }

    private func preview(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 60 ? String(oneLine.prefix(60)) + "…" : oneLine
    }

    // Show banners even though we're technically the "active" app.
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound, .list])
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        // Any click on it or its buttons means "done with this one": clear it everywhere.
        center.removeDeliveredNotifications(withIdentifiers: [r.notification.request.identifier])

        let info = r.notification.request.content.userInfo
        if let a = info["a"] as? String {
            let q = info["q"] as? String ?? ""
            let s = info["s"] as? String ?? ""
            DispatchQueue.main.async {
                if r.actionIdentifier == self.copyAction {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(a, forType: .string)
                } else if r.actionIdentifier == UNNotificationDefaultActionIdentifier {
                    self.onOpen?(q, a, s)
                }
            }
        }
        done()
    }
}
