import Foundation
import AppKit
import Combine

final class AppUpdater: ObservableObject {
    @MainActor @Published var updateStatus: String = ""
    @MainActor @Published var hasUpdate: Bool = false
    @MainActor @Published var latestReleaseURL: URL?

    private let repo = "MeinhartThomas/ClickUpTimerGuard"
    
    init() {}

    @MainActor
    func checkForUpdates(automatic: Bool = false) async {
        if !automatic {
            updateStatus = "Checking for updates..."
        }
        hasUpdate = false
        latestReleaseURL = nil

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if !automatic {
                    updateStatus = "Failed to fetch updates. Please try again later."
                }
                return
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String,
               let htmlUrlString = json["html_url"] as? String,
               let releaseURL = URL(string: htmlUrlString) {
                
                let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                if currentVersion.compare(latestVersion, options: .numeric) == .orderedAscending {
                    hasUpdate = true
                    latestReleaseURL = releaseURL
                    updateStatus = "Update available: \(latestVersion)"
                } else {
                    if !automatic {
                        updateStatus = "App is up to date (\(currentVersion))."
                    }
                }
            } else {
                if !automatic {
                    updateStatus = "Failed to parse update information."
                }
            }
        } catch {
            if !automatic {
                updateStatus = "Update check failed: \(error.localizedDescription)"
            }
        }
    }
    
    func openLatestRelease() {
        if let url = latestReleaseURL {
            NSWorkspace.shared.open(url)
        }
    }
}