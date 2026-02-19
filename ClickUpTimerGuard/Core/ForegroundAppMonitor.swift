import AppKit
import Foundation

protocol ForegroundAppMonitoring {
    func frontmostBundleID() -> String?
}

struct ForegroundAppMonitor: ForegroundAppMonitoring {
    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
