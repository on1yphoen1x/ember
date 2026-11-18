import ServiceManagement
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case lyrics, shelf, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .lyrics: "Lyrics"
        case .shelf: "Shelf"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .lyrics: "quote.bubble"
        case .shelf: "tray.full"
        case .settings: "gearshape"
        }
    }
}

struct MainWindow: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var shelf: Shelf
    @ObservedObject var updater: Updater
    let lockScreen: LockScreenLyrics

    @State private var page: Page? = .lyrics
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var isFullScreen = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(Page.allCases, selection: $page) { page in
                Label(page.title, systemImage: page.symbol)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch page ?? .lyrics {
            case .lyrics:
                LyricsView(lyrics: lyrics, nowPlaying: nowPlaying, isFullScreen: isFullScreen)
                    .toolbar {
                        ToolbarItem {
                            Button {
                                toggleFullScreen()
                            } label: {
                                Label(isFullScreen ? "Exit Full Screen" : "Full Screen Lyrics",
                                      systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            }
                            .help(isFullScreen ? "Exit full screen" : "Show lyrics full screen")
                        }
                    }
            case .shelf:
                ShelfPage(shelf: shelf)
            case .settings:
                SettingsPage(updater: updater, lockScreen: lockScreen)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
            columns = .all
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            if page == .lyrics {
                isFullScreen = true
                columns = .detailOnly
            }
        }
    }

    private func toggleFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) else { return }
        window.toggleFullScreen(nil)
    }
}

struct ShelfPage: View {
    @ObservedObject var shelf: Shelf
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shelf")
                        .font(.system(size: 22, weight: .bold))
                    Text("Files you drop on the notch wait here until you drag them somewhere else.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !shelf.items.isEmpty {
                    Button("AirDrop All") { shelf.airDrop(shelf.items) }
                    Button("Clear") { shelf.clear() }
                }
            }

            if shelf.items.isEmpty {
                Text("Drag files onto the notch or into this window.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfTile(url: url, shelf: shelf)
                                .environment(\.colorScheme, .dark)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

struct SettingsPage: View {
    @ObservedObject var updater: Updater
    let lockScreen: LockScreenLyrics

    @AppStorage("showsMenuBarIcon") private var showsMenuBarIcon = true
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var lockScreenLyrics = false
    @State private var updateMessage: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Flint when you log in", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchesAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show Flint in the menu bar", isOn: $showsMenuBarIcon)
            }

            Section {
                Toggle("Show lyrics on the lock screen", isOn: $lockScreenLyrics)
                    .onChange(of: lockScreenLyrics) { _, enabled in lockScreen.isEnabled = enabled }
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Lyrics come from LRCLIB. The lock screen uses a part of macOS that Apple doesn't officially open to apps, so it may stop working after a macOS update.")
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                LabeledContent("Installed", value: "Build \(updater.currentBuild)")
                if let release = updater.available {
                    Button(updater.isInstalling ? "Installing..." : "Install build \(release.build)") {
                        Task {
                            do {
                                try await updater.install()
                            } catch {
                                updateMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(updater.isInstalling)
                } else {
                    Button("Check for Updates") {
                        Task {
                            let reached = await updater.check()
                            updateMessage = !reached ? "Couldn't reach GitHub." : updater.available == nil ? "You're on the latest build." : nil
                        }
                    }
                }
                if let updateMessage {
                    Text(updateMessage).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { lockScreenLyrics = lockScreen.isEnabled }
    }
}
