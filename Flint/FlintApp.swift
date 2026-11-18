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
            MenuPanel(nowPlaying: appDelegate.nowPlaying, updater: appDelegate.updater)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        island = IslandController(model: IslandModel(nowPlaying: nowPlaying, ember: ember, shelf: shelf))
        _ = lockScreen
    }

    // The notch keeps working after the window is closed; clicking the Dock icon brings it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
