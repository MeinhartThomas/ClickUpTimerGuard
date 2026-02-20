import Foundation
import AppKit
import UserNotifications
import Combine
import ServiceManagement

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
    @Published var availableWorkspacesDescription = "Not loaded"
    @Published var tokenInput = ""
    @Published var startAtLoginEnabled = false
    @Published var startAtLoginErrorMessage: String?

    let settings: AppSettings

    private let activityMonitor: ActivityMonitoring
    private let foregroundAppMonitor: ForegroundAppMonitoring
    private let clickUpClient: ClickUpAPIClient
    private let tokenStore: SecureTokenStore
    private let reminderEngine: ReminderEngine
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationPresenter = ForegroundNotificationPresenter()

    private var schedulerTask: Task<Void, Never>?
    private var appActivationObserver: NSObjectProtocol?
    private var hasShownNotificationsDisabledPrompt = false

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
        startAtLoginEnabled = Self.isStartAtLoginEnabledInSystem()
    }

    func start() {
        startFrontmostAppObserver()
        notificationCenter.delegate = notificationPresenter
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

    func loadWorkspaces() {
        Task { await loadWorkspacesNow() }
    }

    func refreshStartAtLoginStatus() {
        startAtLoginEnabled = Self.isStartAtLoginEnabledInSystem()
    }

    func setStartAtLoginEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            startAtLoginEnabled = false
            startAtLoginErrorMessage = "Start at login requires macOS 13 or newer."
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            startAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            startAtLoginErrorMessage = nil
        } catch {
            startAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            startAtLoginErrorMessage = "Failed to update startup behavior: \(error.localizedDescription)"
        }
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

    private func loadWorkspacesNow() async {
        lastErrorMessage = nil
        availableWorkspacesDescription = "Loading..."

        do {
            guard let token = try tokenStore.loadToken(), !token.isEmpty else {
                availableWorkspacesDescription = "Not loaded"
                lastErrorMessage = "No ClickUp token configured"
                return
            }

            let workspaces = try await clickUpClient.fetchWorkspaces(token: token)
            if workspaces.isEmpty {
                availableWorkspacesDescription = "No workspaces found for this token"
            } else {
                availableWorkspacesDescription = workspaces
                    .map { "\($0.name): \($0.id)" }
                    .joined(separator: "\n")
            }
        } catch {
            availableWorkspacesDescription = "Not loaded"
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
        let initialSettings = await notificationCenter.notificationSettings()
        if initialSettings.authorizationStatus == .notDetermined {
            _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
        }

        let finalSettings = await notificationCenter.notificationSettings()
        if finalSettings.authorizationStatus == .denied {
            lastErrorMessage = "Notifications are disabled for ClickUpTimerGuard in macOS System Settings."
            promptToEnableNotificationsIfNeeded()
        }
    }

    private func sendMissingTimerNotification() async {
        let title = "Start your ClickUp timer"
        let body = "You are actively working, but no ClickUp timer is running."
        await sendNotification(title: title, body: body)
    }

    private func sendNotification(title: String, body: String) async {
        let settings = await notificationCenter.notificationSettings()
        if settings.authorizationStatus == .denied {
            lastErrorMessage = "Notifications are disabled for ClickUpTimerGuard in macOS System Settings."
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
        do {
            try await notificationCenter.add(request)
        } catch {
            lastErrorMessage = "Failed to schedule notification: \(error.localizedDescription)"
        }
    }

    private func promptToEnableNotificationsIfNeeded() {
        guard !hasShownNotificationsDisabledPrompt else { return }
        hasShownNotificationsDisabledPrompt = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Enable Notifications"
        alert.informativeText = "ClickUpTimerGuard needs notifications enabled to remind you when a timer is not running."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openNotificationSettings()
        }
    }

    private func openNotificationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
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

    private static func isStartAtLoginEnabledInSystem() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}

private final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
