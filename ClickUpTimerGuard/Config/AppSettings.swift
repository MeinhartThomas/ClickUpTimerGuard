import Foundation
import Combine

final class AppSettings: ObservableObject {
    private enum Keys {
        static let pollIntervalSeconds = "pollIntervalSeconds"
        static let activityWindowSeconds = "activityWindowSeconds"
        static let workBundleIDsRaw = "workBundleIDsRaw"
        static let clickUpTeamID = "clickUpTeamID"
        static let clickUpUserID = "clickUpUserID"
    }

    @Published var pollIntervalSeconds: Double {
        didSet { defaults.set(pollIntervalSeconds, forKey: Keys.pollIntervalSeconds) }
    }

    @Published var activityWindowSeconds: Double {
        didSet { defaults.set(activityWindowSeconds, forKey: Keys.activityWindowSeconds) }
    }

    @Published var workBundleIDsRaw: String {
        didSet { defaults.set(workBundleIDsRaw, forKey: Keys.workBundleIDsRaw) }
    }

    @Published var clickUpTeamID: String {
        didSet { defaults.set(clickUpTeamID, forKey: Keys.clickUpTeamID) }
    }

    @Published var clickUpUserID: String {
        didSet { defaults.set(clickUpUserID, forKey: Keys.clickUpUserID) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let defaultBundles = [
            "com.microsoft.VSCode",
            "com.google.Chrome",
            "com.apple.Safari",
            "com.brave.Browser"
        ].joined(separator: "\n")

        self.pollIntervalSeconds = defaults.object(forKey: Keys.pollIntervalSeconds) as? Double ?? 45
        self.activityWindowSeconds = defaults.object(forKey: Keys.activityWindowSeconds) as? Double ?? 90
        self.workBundleIDsRaw = defaults.string(forKey: Keys.workBundleIDsRaw) ?? defaultBundles
        self.clickUpTeamID = defaults.string(forKey: Keys.clickUpTeamID) ?? ""
        self.clickUpUserID = defaults.string(forKey: Keys.clickUpUserID) ?? ""
    }

    var workBundleIDs: Set<String> {
        Set(
            workBundleIDsRaw
                .split(whereSeparator: { $0 == "\n" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    @discardableResult
    func addWorkBundleID(_ bundleID: String) -> Bool {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        var existing = workBundleIDsRaw
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !existing.contains(normalized) else {
            return false
        }

        existing.append(normalized)
        workBundleIDsRaw = existing.joined(separator: "\n")
        return true
    }
}
