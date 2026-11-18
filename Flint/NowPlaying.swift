import AppKit

enum MediaSource: String, CaseIterable, Sendable {
    case music
    case spotify

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var scriptName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    var notificationName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}

struct Track: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var source: MediaSource
}

/// What the players broadcast. Music and Spotify both post this on every play, pause and track change,
/// so nothing has to poll while music plays.
private struct PlayerInfo: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var state: String?
    var duration: Double?
    var position: Double?

    init(_ userInfo: [AnyHashable: Any]?, source: MediaSource) {
        title = userInfo?["Name"] as? String
        artist = userInfo?["Artist"] as? String
        album = userInfo?["Album"] as? String
        state = userInfo?["Player State"] as? String
        switch source {
        case .music:
            duration = (userInfo?["Total Time"] as? NSNumber).map { $0.doubleValue / 1000 }
        case .spotify:
            duration = (userInfo?["Duration"] as? NSNumber).map { $0.doubleValue / 1000 }
            position = (userInfo?["Playback Position"] as? NSNumber)?.doubleValue
        }
    }
}

@MainActor
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent = NSColor.white

    private var positionAnchor: Double = 0
    private var positionAnchorDate = Date()
    private var observers: [NSObjectProtocol] = []
    private var artworkKey = ""

    init() {
        for source in MediaSource.allCases {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: source.notificationName, object: nil, queue: .main
            ) { [weak self] note in
                let info = PlayerInfo(note.userInfo, source: source)
                MainActor.assumeIsolated { self?.apply(info, from: source) }
            }
            observers.append(observer)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let source = self.track?.source, source.bundleID == bundleID else { return }
                self.clear()
            }
        })

        Task { self.loadInitialState() }
    }

    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let elapsed = isPlaying ? date.timeIntervalSince(positionAnchorDate) : 0
        return min(max(positionAnchor + elapsed, 0), track.duration)
    }

    func togglePlayPause() {
        guard let source = track?.source else { return }
        isPlaying.toggle()
        anchorPosition(position(at: Date()))
        run("playpause", in: source)
    }

    func nextTrack() {
        guard let source = track?.source else { return }
        run("next track", in: source)
    }

    func previousTrack() {
        guard let source = track?.source else { return }
        run("previous track", in: source)
    }

    func seek(to seconds: Double) {
        guard let source = track?.source else { return }
        anchorPosition(seconds)
        run("set player position to \(seconds)", in: source)
    }

    func open(_ source: MediaSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func refreshPosition() {
        guard let source = track?.source, source.isRunning,
              let value = run("player position", in: source)?.doubleValue else { return }
        anchorPosition(value)
    }

    /// Starts over after the preferred player changes in Settings.
    func reload() {
        clear()
        loadInitialState()
    }

    private func accepts(_ source: MediaSource) -> Bool {
        SourcePreference.current.source.map { $0 == source } ?? true
    }

    private func apply(_ info: PlayerInfo, from source: MediaSource) {
        guard accepts(source) else { return }
        let playing = info.state == "Playing"

        if info.state == "Stopped" || info.title == nil {
            if track?.source == source { clear() }
            return
        }
        // A paused player shouldn't steal the island from one that is still playing.
        if !playing, let current = track, current.source != source, isPlaying { return }

        let next = Track(
            title: info.title ?? "",
            artist: info.artist ?? "",
            album: info.album ?? "",
            duration: info.duration ?? track?.duration ?? 0,
            source: source
        )
        let isNewTrack = next.title != track?.title || next.source != track?.source
        track = next
        isPlaying = playing

        if let position = info.position {
            anchorPosition(position)
        } else if isNewTrack {
            anchorPosition(0)
        } else {
            refreshPosition()
        }

        let key = "\(source.rawValue)|\(next.title)|\(next.album)"
        if key != artworkKey {
            artworkKey = key
            loadArtwork(for: source)
        }
    }

    private func loadInitialState() {
        for source in MediaSource.allCases where source.isRunning && accepts(source) {
            guard let state = run("player state as string", in: source)?.stringValue, state == "playing" || state == "paused",
                  let title = run("name of current track", in: source)?.stringValue else { continue }
            let artist = run("artist of current track", in: source)?.stringValue ?? ""
            let album = run("album of current track", in: source)?.stringValue ?? ""
            let rawDuration = run("duration of current track", in: source)?.doubleValue ?? 0
            // Spotify reports milliseconds, Music reports seconds.
            let duration = source == .spotify ? rawDuration / 1000 : rawDuration

            track = Track(title: title, artist: artist, album: album, duration: duration, source: source)
            isPlaying = state == "playing"
            refreshPosition()
            artworkKey = "\(source.rawValue)|\(title)|\(album)"
            loadArtwork(for: source)
            if isPlaying { break }
        }
    }

    private func loadArtwork(for source: MediaSource) {
        switch source {
        case .music:
            let data = run("raw data of artwork 1 of current track", in: source)?.data
            setArtwork(data.flatMap { NSImage(data: $0) })
        case .spotify:
            guard let link = run("artwork url of current track", in: source)?.stringValue,
                  let url = URL(string: link) else {
                setArtwork(nil)
                return
            }
            let key = artworkKey
            Task {
                let image = try? await URLSession.shared.data(from: url).0
                guard key == artworkKey else { return }
                setArtwork(image.flatMap { NSImage(data: $0) })
            }
        }
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        accent = image?.islandAccent ?? .white
    }

    private func anchorPosition(_ seconds: Double) {
        positionAnchor = seconds
        positionAnchorDate = Date()
    }

    private func clear() {
        track = nil
        isPlaying = false
        artworkKey = ""
        setArtwork(nil)
    }

    /// `tell application` launches the target if it isn't open, so every caller checks it's running first.
    @discardableResult
    private func run(_ command: String, in source: MediaSource) -> NSAppleEventDescriptor? {
        guard source.isRunning else { return nil }
        let script = NSAppleScript(source: "tell application \"\(source.scriptName)\" to \(command)")
        var error: NSDictionary?
        return script?.executeAndReturnError(&error)
    }
}

extension NSImage {
    /// The average colour of the artwork, lifted so it stays readable on the black island.
    var islandAccent: NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }

        let average = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturation * 1.2, 0.85), brightness: max(brightness, 0.82), alpha: 1)
    }
}
