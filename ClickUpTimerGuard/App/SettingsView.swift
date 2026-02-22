import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: GuardController
    @ObservedObject var settings: AppSettings
    @State private var selectedSection: SettingsSection? = .clickUpAPI

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSection ?? .clickUpAPI {
                    case .general:
                        generalSection
                    case .clickUpAPI:
                        clickUpAPISection
                    case .detection:
                        detectionSection
                    case .activeApps:
                        activeAppsSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle((selectedSection ?? .clickUpAPI).title)
        }
        .frame(minWidth: 760, minHeight: 720)
    }

    private var generalSection: some View {
        Group {
            row("Startup") {
                Toggle("Start app on startup", isOn: Binding(
                    get: { controller.startAtLoginEnabled },
                    set: { controller.setStartAtLoginEnabled($0) }
                ))
                .toggleStyle(.checkbox)
            }
            Text("Launches ClickUpTimerGuard automatically when you log in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 192)

            if let error = controller.startAtLoginErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 192)
            }
            
            Divider()
                .padding(.vertical, 8)
                
            row("Updates") {
                VStack(alignment: .leading, spacing: 8) {
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                    Text("Current Version: \(currentVersion)")
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Button("Check for Updates") {
                            Task {
                                await controller.updater.checkForUpdates()
                            }
                        }
                        
                        if controller.updater.hasUpdate {
                            Button("Download Update") {
                                controller.updater.openLatestRelease()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .onAppear {
            controller.refreshStartAtLoginStatus()
        }
    }

    private var clickUpAPISection: some View {
        Group {
            row("Personal API Token") {
                SecureField("", text: $controller.tokenInput)
                    .textFieldStyle(.roundedBorder)
            }
            row("") {
                HStack(spacing: 8) {
                    Button("Save Token") {
                        controller.persistToken()
                    }
                    Button("Delete Token") {
                        controller.deleteToken()
                    }
                }
            }
            row("Team ID (optional)") {
                TextField("", text: $settings.clickUpTeamID)
                    .textFieldStyle(.roundedBorder)
            }
            row("User ID (optional)") {
                TextField("", text: $settings.clickUpUserID)
                    .textFieldStyle(.roundedBorder)
            }
            row("") {
                Button("Load Identity") {
                    controller.loadIdentity()
                }
            }
            row("Resolved Identity") {
                Text(controller.identityDescription)
                    .foregroundStyle(.secondary)
            }
            row("") {
                Button("Load Workspaces") {
                    controller.loadWorkspaces()
                }
            }
            row("Available Workspaces") {
                Text(controller.availableWorkspacesDescription)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    private var detectionSection: some View {
        Group {
            row("Poll interval (seconds)") {
                TextField("", value: $settings.pollIntervalSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            Text("How often the app runs a full check (ClickUp timer state + reminder decision). Lower values check more often.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 192)
            row("Activity window (seconds)") {
                TextField("", value: $settings.activityWindowSeconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            Text("How recent keyboard/mouse input must be for you to count as active. Used with the active app work-app list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 192)
        }
    }

    private var activeAppsSection: some View {
        Group {
            TextEditor(text: $settings.workBundleIDsRaw)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 320, maxHeight: 320)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            Text("Enter one bundle identifier per line.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 180, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case clickUpAPI
    case detection
    case activeApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .clickUpAPI:
            return "ClickUp API"
        case .detection:
            return "Detection"
        case .activeApps:
            return "Active Apps"
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .clickUpAPI:
            return "link"
        case .detection:
            return "timer"
        case .activeApps:
            return "app.badge"
        }
    }
}
