import AppKit
import SwiftUI

/// Shows what's playing on the lock screen: the artwork, a clock and the lyrics.
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
        get { UserDefaults.standard.bool(forKey: SettingsKey.lockScreen) }
        set {
            UserDefaults.standard.set(newValue, forKey: SettingsKey.lockScreen)
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

        let window = self.window ?? makeWindow()
        window.setFrame(screen.frame, display: true)
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
        let host = NSHostingView(rootView: LockScreenView(lyrics: lyrics, nowPlaying: nowPlaying))
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

struct LockScreenView: View {
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var nowPlaying: NowPlaying

    @AppStorage(SettingsKey.lockScreenBackdrop) private var showsBackdrop = true
    @AppStorage(SettingsKey.lockScreenClock) private var showsClock = true
    @AppStorage(SettingsKey.lockScreenBattery) private var showsBattery = true
    @AppStorage(SettingsKey.wordByWord) private var wordByWord = true

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack {
                if showsBackdrop {
                    ArtworkBackdrop(artwork: nowPlaying.artwork, accent: Color(nsColor: nowPlaying.accent))
                }

                TimelineView(.animation(minimumInterval: 0.1)) { context in
                    VStack(spacing: 0) {
                        if showsBackdrop && showsClock {
                            LockClock(date: context.date, accent: Color(nsColor: nowPlaying.accent), showsBattery: showsBattery)
                                .padding(.top, height * 0.07)
                        }
                        Spacer(minLength: 20)
                        nowPlayingCard(at: context.date, height: height)
                        Spacer(minLength: 20)
                        // The password field and Touch ID prompt live down here.
                        Color.clear.frame(height: height * 0.24)
                    }
                }
            }
            .frame(width: geometry.size.width, height: height)
        }
        .environment(\.colorScheme, .dark)
    }

    private func nowPlayingCard(at date: Date, height: CGFloat) -> some View {
        let position = nowPlaying.position(at: date)
        let index = lyrics.currentIndex(at: position + 0.2)
        let lines = lyrics.lines
        let artSize = min(height * 0.22, 240)

        return VStack(spacing: 18) {
            ArtworkView(image: nowPlaying.artwork, cornerRadius: artSize * 0.08)
                .frame(width: artSize, height: artSize)
                .shadow(color: .black.opacity(0.45), radius: 30, y: 14)

            if let track = nowPlaying.track {
                VStack(spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(track.artist)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                LockProgress(position: position, duration: track.duration)
                    .frame(width: artSize)
            }

            VStack(spacing: 10) {
                if let index, lines.indices.contains(index) {
                    let line = lines[index]
                    Group {
                        if line.text.isEmpty {
                            Text("\u{266A}")
                        } else if wordByWord {
                            KaraokeLine(text: line.text, start: line.time, end: lyrics.endTime(of: index), position: position + 0.2)
                        } else {
                            Text(line.text)
                        }
                    }
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .id(line.id)
                    .transition(.opacity.combined(with: .offset(y: 12)))

                    if lines.indices.contains(index + 1) {
                        Text(lines[index + 1].text)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(minHeight: 90, alignment: .top)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: index)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .shadow(color: .black.opacity(0.35), radius: 10)
        .padding(.horizontal, 80)
    }
}

/// The artwork blown up to fill the screen, fading out before the bottom so
/// the password field stays visible.
struct ArtworkBackdrop: View {
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        ZStack {
            Color.black
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 40)
                    .saturation(1.15)
                    .opacity(0.8)
            } else {
                accent.opacity(0.25)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .mask(
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.66), .init(color: .clear, location: 0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct LockClock: View {
    let date: Date
    let accent: Color
    let showsBattery: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .font(.system(size: 112, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(LinearGradient(colors: [.white, accent.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            if showsBattery, let battery = Battery.read(at: date) {
                Label("\(battery.percent)%", systemImage: battery.isCharging ? "bolt.fill" : battery.symbol)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 4)
            }
        }
    }
}

struct LockProgress: View {
    let position: Double
    let duration: Double

    var body: some View {
        let fraction = duration > 0 ? min(position / duration, 1) : 0
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white.opacity(0.85)).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}
