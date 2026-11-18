import AppKit

/// Follows recordings made in Ember, the recording app, and sends it pause, resume and stop.
@MainActor
final class EmberLink: ObservableObject {
    enum State: String, Sendable {
        case recording, paused, idle
    }

    private nonisolated static let stateName = Notification.Name("app.phoenixclips.ember.recordingState")
    private nonisolated static let commandName = Notification.Name("app.phoenixclips.ember.command")
    private nonisolated static let bundleID = "app.phoenixclips.PhoenixRecording"

    @Published private(set) var state = State.idle

    private var elapsedAnchor: TimeInterval = 0
    private var anchorDate = Date()
    private var observers: [NSObjectProtocol] = []

    var isActive: Bool { state != .idle }

    init() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Self.stateName, object: nil, queue: .main
        ) { [weak self] note in
            let state = (note.userInfo?["state"] as? String).flatMap(State.init(rawValue:)) ?? .idle
            let elapsed = (note.userInfo?["elapsed"] as? NSNumber)?.doubleValue ?? 0
            let sentAt = (note.userInfo?["sentAt"] as? NSNumber)?.doubleValue
            MainActor.assumeIsolated { self?.apply(state, elapsed: elapsed, sentAt: sentAt) }
        })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard bundleID == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.apply(.idle, elapsed: 0, sentAt: nil) }
        })

        // Picks up a recording that was already running when Flint opened.
        send("status")
    }

    func elapsed(at date: Date) -> TimeInterval {
        state == .recording ? elapsedAnchor + max(date.timeIntervalSince(anchorDate), 0) : elapsedAnchor
    }

    func togglePause() {
        send(state == .paused ? "resume" : "pause")
    }

    func stop() {
        send("stop")
    }

    private func apply(_ state: State, elapsed: TimeInterval, sentAt: TimeInterval?) {
        elapsedAnchor = elapsed
        anchorDate = sentAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
        self.state = state
    }

    private func send(_ action: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Self.commandName, object: nil, userInfo: ["action": action], deliverImmediately: true
        )
    }
}
