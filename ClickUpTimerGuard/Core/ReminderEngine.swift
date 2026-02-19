import Foundation

struct ReminderInput {
    let isActiveWorkContext: Bool
    let timerRunning: Bool
}

enum ReminderDecision: Equatable {
    case notify
    case noAction
    case snoozed
}

final class ReminderEngine {
    private var hasShownReminderForCurrentContext = false
    private(set) var snoozedUntil: Date?

    func evaluate(_ input: ReminderInput, now: Date = Date()) -> ReminderDecision {
        if let snoozedUntil, now < snoozedUntil {
            return .snoozed
        }

        if !input.isActiveWorkContext {
            hasShownReminderForCurrentContext = false
            return .noAction
        }

        if input.timerRunning {
            hasShownReminderForCurrentContext = false
            return .noAction
        }

        if hasShownReminderForCurrentContext {
            return .noAction
        }

        hasShownReminderForCurrentContext = true
        return .notify
    }

    func snooze(until date: Date) {
        snoozedUntil = date
    }

    func clearSnooze() {
        snoozedUntil = nil
    }
}
