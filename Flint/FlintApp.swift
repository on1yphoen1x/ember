import SwiftUI

@main
struct FlintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showsMenuBarIcon") private var showsMenuBarIcon = true

    var body: some Scene {
        Window("Flint", id: "main") {
            MainWindow(
                nowPlaying: appDelegate.nowPlaying,
                lyrics: appDelegate.lyrics,
                shelf: appDelegate.shelf,
                updater: appDelegate.updater,
                lockScreen: appDelegate.lockScreen
            )
        }
        .defaultSize(width: 860, height: 600)

        MenuBarExtra("Flint", systemImage: "rectangle.topthird.inset.filled", isInserted: $showsMenuBarIcon) {
            MenuPanel(nowPlaying: appDelegate.nowPlaying, ember: appDelegate.ember, updater: appDelegate.updater)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let nowPlaying = NowPlaying()
    let updater = Updater()
    let ember = EmberLink()
    let shelf = Shelf()
    lazy var lyrics = Lyrics(nowPlaying: nowPlaying)
    lazy var lockScreen = LockScreenLyrics(lyrics: lyrics, nowPlaying: nowPlaying)
    private var island: IslandController?
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = IslandModel(nowPlaying: nowPlaying, ember: ember, shelf: shelf)
        island = IslandController(model: model)
        _ = lockScreen

        if !UserDefaults.standard.bool(forKey: SettingsKey.hasWelcomed) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6)) { model.welcome() }
        }

        // Closing the window hides Flint from the Dock; the notch and menu bar keep running until Quit.
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            let isMain = (note.object as? NSWindow)?.identifier?.rawValue.contains("main") == true
            guard isMain else { return }
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.accessory)
                UserDefaults.standard.set(true, forKey: "showsMenuBarIcon")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MainWindowOpener.open() }
        return true
    }
}
