import Foundation
import AppKit
import UserNotifications
import Combine

@MainActor
final class GuardController: ObservableObject {
    @Published var lastCheckDescription = "Not checked yet"
    @Published var lastErrorMessage: String?
    @Published var currentFrontmostBundleID = "-"
    @Published var isActiveWorkContext = false
    @Published var isTimerRunning = false
    @Published var isSnoozeActive = false
    @Published var clearSnoozeButtonTitle = "Clear Snooze"
    @Published var identityDescription = "Not resolved"
    @Published var tokenInput = ""

    let settings: AppSettings

    private let activityMonitor: ActivityMonitoring
    private let foregroundAppMonitor: ForegroundAppMonitoring
    private let clickUpClient: ClickUpAPIClient
    private let tokenStore: SecureTokenStore
    private let reminderEngine: ReminderEngine
    private var notificationCenter: UNUserNotificationCenter? {
        guard Self.isRunningAsAppBundle else { return nil }
        return UNUserNotificationCenter.current()
    }

    private var schedulerTask: Task<Void, Never>?
    private var appActivationObserver: NSObjectProtocol?

    init(
        settings: AppSettings = AppSettings(),
        activityMonitor: ActivityMonitoring = ActivityMonitor(),
        foregroundAppMonitor: ForegroundAppMonitoring = ForegroundAppMonitor(),
        clickUpClient: ClickUpAPIClient = ClickUpAPIClient(),
        tokenStore: SecureTokenStore = SecureTokenStore(),
        reminderEngine: ReminderEngine = ReminderEngine()
    ) {
        self.settings = settings
        self.activityMonitor = activityMonitor
        self.foregroundAppMonitor = foregroundAppMonitor
        self.clickUpClient = clickUpClient
        self.tokenStore = tokenStore
        self.reminderEngine = reminderEngine

        tokenInput = (try? tokenStore.loadToken()) ?? ""
    }

    func start() {
        startFrontmostAppObserver()
        Task { await requestNotificationAuthorizationIfNeeded() }
        startScheduler()
    }

    func stop() {
        stopFrontmostAppObserver()
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runCheck()
                let seconds = max(15, self.settings.pollIntervalSeconds)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func checkNow() {
        Task { await runCheck() }
    }

    func sendTestNotification() {
        Task {
            await sendNotification(
                title: "ClickUp Timer Guard Test",
                body: "This is a test notification from the menu bar dropdown."
            )
            lastCheckDescription = "Sent test notification at \(Self.dateFormatter.string(from: Date()))"
        }
    }

    func snooze(minutes: Int) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        reminderEngine.snooze(until: until)
        refreshSnoozeState()
        lastCheckDescription = "Snoozed until \(Self.dateFormatter.string(from: until))"
    }

    func snooze(hours: Int) {
        let until = Date().addingTimeInterval(TimeInterval(hours * 60 * 60))
        reminderEngine.snooze(until: until)
        refreshSnoozeState()
        lastCheckDescription = "Snoozed until \(Self.dateFormatter.string(from: until))"
    }

    func snoozeRestOfDay() {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let until = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(8 * 60 * 60)

        reminderEngine.snooze(until: until)
        refreshSnoozeState()
        lastCheckDescription = "Snoozed until end of day"
    }

    func clearSnooze() {
        reminderEngine.clearSnooze()
        refreshSnoozeState()
    }

    func addCurrentFrontmostAppToWorkContext() {
        let bundleID = (foregroundAppMonitor.frontmostBundleID() ?? currentFrontmostBundleID)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !bundleID.isEmpty, bundleID != "-" else {
            lastErrorMessage = "No active app bundle ID is available."
            return
        }

        let added = settings.addWorkBundleID(bundleID)
        if added {
            lastErrorMessage = nil
            lastCheckDescription = "Added \(bundleID) to work app IDs"
        } else {
            lastCheckDescription = "\(bundleID) is already in work app IDs"
        }
    }

    func persistToken() {
        do {
            try tokenStore.saveToken(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines))
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteToken() {
        do {
            try tokenStore.deleteToken()
            tokenInput = ""
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func loadIdentity() {
        Task { await loadIdentityNow() }
    }

    private func runCheck() async {
        lastErrorMessage = nil
        let now = Date()
        refreshSnoozeState(now: now)

        refreshFrontmostState()

        do {
            guard let token = try tokenStore.loadToken(), !token.isEmpty else {
                isTimerRunning = false
                lastCheckDescription = "No ClickUp token configured"
                return
            }

            let identity = try await resolveAndApplyIdentity(token: token)

            let running = try await clickUpClient.hasRunningTimer(token: token, identity: identity)
            isTimerRunning = running

            let decision = reminderEngine.evaluate(
                ReminderInput(
                    isActiveWorkContext: isActiveWorkContext,
                    timerRunning: running
                ),
                now: now
            )

            switch decision {
            case .notify:
                await sendMissingTimerNotification()
            case .noAction, .snoozed:
                break
            }

            lastCheckDescription = "Last check: \(Self.dateFormatter.string(from: now))"
        } catch {
            lastErrorMessage = error.localizedDescription
            lastCheckDescription = "Last check failed: \(Self.dateFormatter.string(from: now))"
        }
    }

    private func loadIdentityNow() async {
        lastErrorMessage = nil
        identityDescription = "Resolving..."

        do {
            guard let token = try tokenStore.loadToken(), !token.isEmpty else {
                identityDescription = "Not resolved"
                lastErrorMessage = "No ClickUp token configured"
                return
            }

            _ = try await resolveAndApplyIdentity(token: token)
            lastCheckDescription = "Identity loaded: \(Self.dateFormatter.string(from: Date()))"
        } catch {
            identityDescription = "Not resolved"
            lastErrorMessage = error.localizedDescription
        }
    }

    private func resolveAndApplyIdentity(token: String) async throws -> ClickUpIdentity {
        let identity = try await clickUpClient.resolveIdentity(
            token: token,
            preferredTeamID: settings.clickUpTeamID,
            preferredUserID: settings.clickUpUserID
        )

        identityDescription = "Team \(identity.teamID) / User \(identity.userID)"
        if settings.clickUpTeamID.isEmpty { settings.clickUpTeamID = identity.teamID }
        if settings.clickUpUserID.isEmpty { settings.clickUpUserID = identity.userID }
        return identity
    }

    private func requestNotificationAuthorizationIfNeeded() async {
        guard let notificationCenter else { return }
        let settings = await notificationCenter.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
        }
    }

    private func sendMissingTimerNotification() async {
        let title = "Start your ClickUp timer"
        let body = "You are actively working, but no ClickUp timer is running."
        await sendNotification(title: title, body: body)
    }

    private func sendNotification(title: String, body: String) async {
        guard let notificationCenter else {
            sendAppleScriptNotification(title: title, body: body)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await notificationCenter.add(request)
    }

    private func sendAppleScriptNotification(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "display notification \(appleScriptStringLiteral(body)) with title \(appleScriptStringLiteral(title))"
        ]
        try? process.run()
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static var isRunningAsAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func startFrontmostAppObserver() {
        guard appActivationObserver == nil else { return }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshFrontmostState()
            }
        }
        refreshFrontmostState()
    }

    private func stopFrontmostAppObserver() {
        guard let appActivationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        self.appActivationObserver = nil
    }

    private func refreshFrontmostState() {
        let frontmostBundleID = foregroundAppMonitor.frontmostBundleID() ?? "-"
        currentFrontmostBundleID = frontmostBundleID
        let activeInput = activityMonitor.isUserRecentlyActive(within: settings.activityWindowSeconds)
        let frontmostIsWorkApp = settings.workBundleIDs.contains(frontmostBundleID)
        isActiveWorkContext = activeInput && frontmostIsWorkApp
    }

    private func refreshSnoozeState(now: Date = Date()) {
        if let snoozedUntil = reminderEngine.snoozedUntil {
            isSnoozeActive = now < snoozedUntil
            if isSnoozeActive {
                clearSnoozeButtonTitle = "Clear Snooze (\(remainingSnoozeLabel(until: snoozedUntil, now: now)))"
            } else {
                clearSnoozeButtonTitle = "Clear Snooze"
            }
        } else {
            isSnoozeActive = false
            clearSnoozeButtonTitle = "Clear Snooze"
        }
    }

    private func remainingSnoozeLabel(until: Date, now: Date) -> String {
        let remaining = max(0, Int(until.timeIntervalSince(now)))
        if remaining >= 3600 {
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            if minutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(minutes)m"
        }
        let minutes = max(1, remaining / 60)
        return "\(minutes)m"
    }
}
