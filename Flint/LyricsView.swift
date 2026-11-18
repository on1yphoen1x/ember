import SwiftUI

struct LyricsView: View {
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var nowPlaying: NowPlaying
    var isFullScreen = false

    var body: some View {
        ZStack {
            LyricsBackdrop(artwork: nowPlaying.artwork, accent: Color(nsColor: nowPlaying.accent))

            VStack(spacing: 0) {
                if let track = nowPlaying.track {
                    HStack(spacing: 14) {
                        ArtworkView(image: nowPlaying.artwork, cornerRadius: 8)
                            .frame(width: isFullScreen ? 64 : 48, height: isFullScreen ? 64 : 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: isFullScreen ? 20 : 15, weight: .semibold))
                            Text(track.artist)
                                .font(.system(size: isFullScreen ? 15 : 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, isFullScreen ? 60 : 28)
                    .padding(.top, isFullScreen ? 40 : 24)
                }

                lyricsBody(for: lyrics.content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .task(id: nowPlaying.track?.title) {
            // Keeps the timing honest while lyrics are on screen; the players don't report seeks.
            while !Task.isCancelled {
                nowPlaying.refreshPosition()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @ViewBuilder
    private func lyricsBody(for content: Lyrics.Content) -> some View {
        switch content {
        case .synced(let lines):
            SyncedLyrics(lines: lines, lyrics: lyrics, nowPlaying: nowPlaying, isFullScreen: isFullScreen)
        case .plain(let lines):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These lyrics aren't timed, so they won't follow along.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: isFullScreen ? 30 : 20, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(isFullScreen ? 60 : 28)
            }
        case .loading:
            ProgressView().controlSize(.small)
        case .instrumental:
            message("This one's instrumental.")
        case .notFound:
            message("No lyrics found for this song.")
        case .none:
            message("Play something in Apple Music or Spotify to see its lyrics here.")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: isFullScreen ? 22 : 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding()
    }
}

struct SyncedLyrics: View {
    let lines: [Lyrics.Line]
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var nowPlaying: NowPlaying
    let isFullScreen: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !nowPlaying.isPlaying)) { context in
            let current = lyrics.currentIndex(at: nowPlaying.position(at: context.date) + 0.2)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: isFullScreen ? 26 : 16) {
                        Color.clear.frame(height: isFullScreen ? 160 : 60)
                        ForEach(lines) { line in
                            let isCurrent = line.id == current
                            Text(line.text.isEmpty ? "\u{266A}" : line.text)
                                .font(.system(size: isFullScreen ? 46 : 26, weight: .bold))
                                .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.32))
                                .scaleEffect(isCurrent ? 1 : 0.96, anchor: .leading)
                                .blur(radius: isCurrent || !isFullScreen ? 0 : 0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                                .onTapGesture { nowPlaying.seek(to: line.time) }
                                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isCurrent)
                        }
                        Color.clear.frame(height: isFullScreen ? 320 : 160)
                    }
                    .padding(.horizontal, isFullScreen ? 60 : 28)
                }
                .onChange(of: current) { _, index in
                    guard let index else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                        proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.35))
                    }
                }
            }
        }
    }
}

struct LyricsBackdrop: View {
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        ZStack {
            Color.black
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 80)
                    .opacity(0.55)
            } else {
                accent.opacity(0.18)
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .clipped()
    }
}
