import SwiftUI

struct CompactMediaView: View {
    @ObservedObject var nowPlaying: NowPlaying
    let gap: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !nowPlaying.isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 0) {
                SpinningArtwork(image: nowPlaying.artwork, time: time)
                    .frame(width: IslandModel.compactWing, alignment: .center)
                Spacer(minLength: gap)
                Waveform(time: time, color: Color(nsColor: nowPlaying.accent), maxHeight: min(height * 0.45, 14))
                    .frame(width: IslandModel.compactWing, alignment: .center)
            }
            .frame(height: height)
        }
    }
}

struct SpinningArtwork: View {
    let image: NSImage?
    let time: TimeInterval

    var body: some View {
        ArtworkView(image: image, cornerRadius: 11)
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .overlay(Circle().fill(.black).frame(width: 5, height: 5))
            .rotationEffect(.degrees(time.truncatingRemainder(dividingBy: 9) / 9 * 360))
    }
}

/// Four bars driven by overlapping sine waves. The players don't expose levels,
/// so this suggests movement rather than measuring it.
struct Waveform: View {
    let time: TimeInterval
    let color: Color
    let maxHeight: CGFloat

    private static let bars: [(speed: Double, phase: Double)] = [(5.1, 0), (7.3, 1.7), (6.2, 3.1), (8.4, 4.4)]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Self.bars.indices, id: \.self) { index in
                let bar = Self.bars[index]
                let level = 0.3 + 0.7 * abs(sin(time * bar.speed + bar.phase) * cos(time * bar.speed * 0.37))
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: max(3, maxHeight * level))
            }
        }
        .frame(height: maxHeight)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct MediaPlayerView: View {
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        if let track = nowPlaying.track {
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    ArtworkView(image: nowPlaying.artwork, cornerRadius: 10)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color(nsColor: nowPlaying.accent).opacity(0.35), radius: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !nowPlaying.isPlaying)) { context in
                        Waveform(
                            time: context.date.timeIntervalSinceReferenceDate,
                            color: Color(nsColor: nowPlaying.accent),
                            maxHeight: nowPlaying.isPlaying ? 18 : 4
                        )
                    }
                    .frame(width: 22)
                }

                Scrubber(nowPlaying: nowPlaying, duration: track.duration)

                HStack(spacing: 34) {
                    TransportButton(symbol: "backward.fill", size: 15, action: { nowPlaying.previousTrack() })
                    TransportButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 22, action: { nowPlaying.togglePlayPause() })
                    TransportButton(symbol: "forward.fill", size: 15, action: { nowPlaying.nextTrack() })
                }
            }
        } else {
            IdleView(nowPlaying: nowPlaying)
        }
    }
}

struct Scrubber: View {
    @ObservedObject var nowPlaying: NowPlaying
    let duration: Double
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !nowPlaying.isPlaying || dragFraction != nil)) { context in
            let position = dragFraction.map { $0 * duration } ?? nowPlaying.position(at: context.date)
            let fraction = duration > 0 ? position / duration : 0

            HStack(spacing: 8) {
                Text(Self.format(position))
                    .frame(width: 34, alignment: .trailing)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(.white)
                            .frame(width: geometry.size.width * fraction)
                    }
                    .frame(height: dragFraction == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragFraction = min(max(value.location.x / geometry.size.width, 0), 1)
                            }
                            .onEnded { _ in
                                if let dragFraction { nowPlaying.seek(to: dragFraction * duration) }
                                dragFraction = nil
                            }
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragFraction == nil)
                }
                .frame(height: 14)

                Text("-" + Self.format(max(duration - position, 0)))
                    .frame(width: 38, alignment: .leading)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IdleView: View {
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        VStack(spacing: 12) {
            Text("Nothing playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 10) {
                ForEach(MediaSource.allCases.filter(\.isInstalled), id: \.self) { source in
                    Button("Open \(source.scriptName)") { nowPlaying.open(source) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
