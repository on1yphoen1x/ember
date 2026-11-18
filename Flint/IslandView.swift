import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var ember: EmberLink

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    var body: some View {
        let size = model.size
        let isVisible = model.isExpanded || model.showsCompact

        ZStack(alignment: .top) {
            IslandShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 14, y: 6)
                .opacity(isVisible ? 1 : 0)

            content
                .frame(width: max(size.width - model.topRadius * 2, 0), height: size.height, alignment: .top)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(spring, value: model.isExpanded)
        .animation(spring, value: model.showsCompact)
        .animation(spring, value: model.showsRecording)
        .animation(spring, value: model.notchSize)
    }

    @ViewBuilder
    private var content: some View {
        if model.isExpanded && model.showsRecording {
            RecordingPanelView(ember: ember)
                .padding(.top, model.hasNotch ? model.notchSize.height : 8)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        } else if model.isExpanded {
            MediaPlayerView(nowPlaying: nowPlaying)
                .padding(.top, model.hasNotch ? model.notchSize.height + 4 : 12)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        } else if model.showsRecording {
            CompactRecordingView(ember: ember, gap: model.gap, height: model.notchSize.height)
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(spring) { model.setExpanded(true) }
                }
        } else if model.showsCompact {
            CompactMediaView(nowPlaying: nowPlaying, gap: model.gap, height: model.notchSize.height)
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(spring) { model.setExpanded(true) }
                }
        }
    }
}
