import CoreGraphics
import Foundation

protocol ActivityMonitoring {
    func isUserRecentlyActive(within seconds: TimeInterval) -> Bool
}

struct ActivityMonitor: ActivityMonitoring {
    func isUserRecentlyActive(within seconds: TimeInterval) -> Bool {
        let state = CGEventSourceStateID.combinedSessionState
        let eventTypes: [CGEventType] = [
            .keyDown,
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel
        ]

        let minimumIdle = eventTypes
            .map { CGEventSource.secondsSinceLastEventType(state, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude

        return minimumIdle <= seconds
    }
}
