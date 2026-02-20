import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var controller: GuardController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.isTimerRunning ? "Timer: Running" : "Timer: Not Running")
            Text(controller.isActiveWorkContext ? "Working: Active" : "Working: Inactive")
            Text("Active App: \(controller.currentFrontmostBundleID)")
                .lineLimit(1)
                .truncationMode(.middle)
            Text(controller.lastCheckDescription)
                .foregroundStyle(.secondary)

            if let error = controller.lastErrorMessage, !error.isEmpty {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
            }

            Divider()

            if !controller.isSnoozeActive {
                Menu {
                    Button("5 mins") {
                        controller.snooze(minutes: 5)
                    }
                    Button("10 mins") {
                        controller.snooze(minutes: 10)
                    }
                    Button("30 mins") {
                        controller.snooze(minutes: 30)
                    }
                    Divider()
                    Button("1 hour") {
                        controller.snooze(hours: 1)
                    }
                    Button("2 hours") {
                        controller.snooze(hours: 2)
                    }
                    Button("4 hours") {
                        controller.snooze(hours: 4)
                    }
                    Button("8 hours") {
                        controller.snooze(hours: 8)
                    }
                    Divider()
                    Button("Rest of day") {
                        controller.snoozeRestOfDay()
                    }
                } label: {
                    Text("Snooze for...")
                }
            }

            if controller.isSnoozeActive {
                Button(controller.clearSnoozeButtonTitle) {
                    controller.clearSnooze()
                }
            }

            if shouldShowAddActiveAppButton {
                Button("Add Active App to Work IDs") {
                    controller.addCurrentFrontmostAppToWorkContext()
                }
            }

            Button("Open Settings") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private var shouldShowAddActiveAppButton: Bool {
        let bundleID = controller.currentFrontmostBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, bundleID != "-" else { return false }
        return !controller.settings.workBundleIDs.contains(bundleID)
    }

}
