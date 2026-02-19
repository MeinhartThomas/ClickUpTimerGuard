import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ClickUpTimerGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = GuardController()

    var body: some Scene {
        MenuBarExtra("Timer Guard", image: "MenuBarIcon") {
            MenuBarView(controller: controller)
                .onAppear {
                    controller.start()
                }
                .onDisappear {
                    controller.stop()
                }
        }

        Window("Settings", id: "settings") {
            SettingsView(controller: controller, settings: controller.settings)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 600, height: 500)
    }
}
