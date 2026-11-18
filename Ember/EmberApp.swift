import SwiftUI

@main
struct EmberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Ember", systemImage: "rectangle.topthird.inset.filled") {
            MenuPanel(nowPlaying: appDelegate.nowPlaying, updater: appDelegate.updater)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let nowPlaying = NowPlaying()
    let updater = Updater()
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        island = IslandController(model: IslandModel(nowPlaying: nowPlaying))
    }
}
