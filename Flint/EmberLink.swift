import AppKit

/// Follows recordings made in Ember, the recording app, and sends it pause, resume and stop.
@MainActor
final class EmberLink: ObservableObject {
    enum State: String, Sendable {
        case recording, paused, idle
    }

    private nonisolated static let stateName = Notification.Name("app.phoenixclips.ember.recordingState")
    private nonisolated static let commandName = Notification.Name("app.phoenixclips.ember.command")
    private nonisolated static let clipSavedName = Notification.Name("app.phoenixclips.ember.clipSaved")
    private nonisolated static let bundleID = "app.phoenixclips.PhoenixRecording"

    @Published private(set) var state = State.idle
    @Published private(set) var isRunning = false
    @Published private(set) var isClipping = false
    @Published private(set) var justSavedClip = false

    private var elapsedAnchor: TimeInterval = 0
    private var anchorDate = Date()
    private var observers: [NSObjectProtocol] = []
    private var savedClipTask: Task<Void, Never>?

    var isActive: Bool { state != .idle }

    init() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Self.stateName, object: nil, queue: .main
        ) { [weak self] note in
            let state = (note.userInfo?["state"] as? String).flatMap(State.init(rawValue:)) ?? .idle
            let elapsed = (note.userInfo?["elapsed"] as? NSNumber)?.doubleValue ?? 0
            let sentAt = (note.userInfo?["sentAt"] as? NSNumber)?.doubleValue
            let clipping = (note.userInfo?["clipping"] as? NSNumber)?.boolValue ?? false
            MainActor.assumeIsolated {
                self?.isRunning = true
                self?.isClipping = clipping
                self?.apply(state, elapsed: elapsed, sentAt: sentAt)
            }
        })

        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Self.clipSavedName, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showClipSaved() }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard bundleID == Self.bundleID else { return }
            MainActor.assumeIsolated {
                self?.isRunning = true
                self?.send("status")
            }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard bundleID == Self.bundleID else { return }
            MainActor.assumeIsolated {
                self?.isRunning = false
                self?.isClipping = false
                self?.apply(.idle, elapsed: 0, sentAt: nil)
            }
        })

        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty

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

    func saveClip() {
        send("clip")
    }

    func startRecording() {
        send("record")
    }

    func openEmber() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showClipSaved() {
        savedClipTask?.cancel()
        justSavedClip = true
        savedClipTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            justSavedClip = false
        }
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
