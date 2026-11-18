import AppKit
import SwiftUI

/// Shows the current lyric line on the lock screen.
///
/// macOS has no public way for apps to draw there. This moves a window into a
/// private SkyLight space that sits at the lock screen's level, which is the same
/// approach other notch apps use. If Apple removes these functions the feature
/// quietly does nothing.
@MainActor
final class LockScreenLyrics {
    private let lyrics: Lyrics
    private let nowPlaying: NowPlaying
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var space: Int32?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "lockScreenLyrics") }
        set {
            UserDefaults.standard.set(newValue, forKey: "lockScreenLyrics")
            if !newValue { hide() }
        }
    }

    init(lyrics: Lyrics, nowPlaying: NowPlaying) {
        self.lyrics = lyrics
        self.nowPlaying = nowPlaying

        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked() }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
    }

    private func screenLocked() {
        guard isEnabled, nowPlaying.track != nil, let screen = NSScreen.main else { return }

        let size = CGSize(width: min(screen.frame.width - 120, 900), height: 170)
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.2,
            width: size.width,
            height: size.height
        )

        let window = self.window ?? makeWindow()
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        moveToLockScreen(window)
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: LockScreenLyricsView(lyrics: lyrics, nowPlaying: nowPlaying))
        host.sizingOptions = []
        window.contentView = host
        return window
    }

    private func moveToLockScreen(_ window: NSWindow) {
        guard let api = SkyLight.shared else { return }
        let connection = api.mainConnection()
        if space == nil {
            let created = api.spaceCreate(connection, 1, 0)
            // 400 is the level the lock screen draws its own notifications at.
            _ = api.spaceSetAbsoluteLevel(connection, created, 400)
            _ = api.showSpaces(connection, [created] as CFArray)
            space = created
        }
        if let space {
            _ = api.addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        }
    }
}

private struct SkyLight {
    typealias MainConnection = @convention(c) () -> Int32
    typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    let mainConnection: MainConnection
    let spaceCreate: SpaceCreate
    let spaceSetAbsoluteLevel: SpaceSetAbsoluteLevel
    let showSpaces: ShowSpaces
    let addWindows: AddWindows

    @MainActor static let shared: SkyLight? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let main = load("SLSMainConnectionID", as: MainConnection.self),
              let create = load("SLSSpaceCreate", as: SpaceCreate.self),
              let level = load("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = load("SLSShowSpaces", as: ShowSpaces.self),
              let add = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self) else { return nil }
        return SkyLight(mainConnection: main, spaceCreate: create, spaceSetAbsoluteLevel: level, showSpaces: show, addWindows: add)
    }()
}

struct LockScreenLyricsView: View {
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let index = lyrics.currentIndex(at: nowPlaying.position(at: context.date) + 0.2)
            let lines = lyrics.lines
            VStack(spacing: 10) {
                if let index, lines.indices.contains(index) {
                    Text(lines[index].text.isEmpty ? "\u{266A}" : lines[index].text)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .id(lines[index].id)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    if lines.indices.contains(index + 1) {
                        Text(lines[index + 1].text)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                } else if let track = nowPlaying.track {
                    Text(track.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text(track.artist)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.5), radius: 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: index)
        }
    }
}
