import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    enum Tab: Hashable {
        case media, shelf, recording
    }

    static let compactWing: CGFloat = 38
    static let recordingWing: CGFloat = 66
    static let expandedWidth: CGFloat = 460
    static let expandedContentHeight: CGFloat = 124

    @Published var notchSize = CGSize(width: 0, height: 24)
    @Published var hasNotch = false
    @Published var tab = Tab.media
    @Published var isDropTargeted = false
    @Published private(set) var isExpanded = false

    let nowPlaying: NowPlaying
    let ember: EmberLink
    let shelf: Shelf

    init(nowPlaying: NowPlaying, ember: EmberLink, shelf: Shelf) {
        self.nowPlaying = nowPlaying
        self.ember = ember
        self.shelf = shelf
    }

    /// A recording takes the island over from music until it stops.
    var showsRecording: Bool {
        ember.isActive
    }

    var showsCompact: Bool {
        showsRecording || (nowPlaying.isPlaying && nowPlaying.track != nil)
    }

    var tabs: [Tab] {
        showsRecording ? [.recording, .media, .shelf] : [.media, .shelf]
    }

    var topRadius: CGFloat {
        isExpanded ? 14 : 6
    }

    var bottomRadius: CGFloat {
        if isExpanded { return 30 }
        return hasNotch ? 10 : notchSize.height / 2
    }

    /// The space the hardware notch takes up between the left and right halves of the compact pill.
    var gap: CGFloat {
        hasNotch ? notchSize.width : 28
    }

    var headerHeight: CGFloat {
        hasNotch ? notchSize.height : 30
    }

    var size: CGSize {
        if isExpanded {
            let width = max(Self.expandedWidth, notchSize.width + 220)
            return CGSize(width: width + topRadius * 2, height: headerHeight + Self.expandedContentHeight + 14)
        }
        if showsCompact {
            let wing = showsRecording ? Self.recordingWing : Self.compactWing
            return CGSize(width: gap + wing * 2 + topRadius * 2, height: notchSize.height)
        }
        return hasNotch ? CGSize(width: notchSize.width + topRadius * 2, height: notchSize.height) : .zero
    }

    func setExpanded(_ expanded: Bool, for preferred: Tab? = nil) {
        if let preferred { tab = preferred }
        guard expanded != isExpanded else { return }
        if expanded {
            if preferred == nil { tab = defaultTab }
            nowPlaying.refreshPosition()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } else {
            isDropTargeted = false
        }
        isExpanded = expanded
    }

    private var defaultTab: Tab {
        if showsRecording { return .recording }
        if nowPlaying.track == nil && !shelf.items.isEmpty { return .shelf }
        return .media
    }
}
