import ServiceManagement
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var updater: Updater
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var updateMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ArtworkView(image: nowPlaying.artwork, cornerRadius: 6)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.track?.title ?? "Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                    if let artist = nowPlaying.track?.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if nowPlaying.track != nil {
                    Button {
                        nowPlaying.togglePlayPause()
                    } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Divider()

            Toggle("Open at login", isOn: $launchesAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
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
                Button("Check for updates") {
                    Task {
                        let reached = await updater.check()
                        updateMessage = !reached ? "Couldn't reach GitHub." : updater.available == nil ? "You're on the latest build." : nil
                    }
                }
            }

            if let updateMessage {
                Text(updateMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("Build \(updater.currentBuild)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit Ember") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
