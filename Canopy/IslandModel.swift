import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    static let compactWing: CGFloat = 38
    static let expandedSize = CGSize(width: 440, height: 132)

    @Published var notchSize = CGSize(width: 0, height: 24)
    @Published var hasNotch = false
    @Published private(set) var isExpanded = false

    let nowPlaying: NowPlaying

    init(nowPlaying: NowPlaying) {
        self.nowPlaying = nowPlaying
    }

    var showsCompact: Bool {
        nowPlaying.isPlaying && nowPlaying.track != nil
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

    var size: CGSize {
        if isExpanded {
            let width = max(Self.expandedSize.width, notchSize.width + 200)
            let height = (hasNotch ? notchSize.height : 6) + Self.expandedSize.height
            return CGSize(width: width + topRadius * 2, height: height)
        }
        if showsCompact {
            return CGSize(width: gap + Self.compactWing * 2 + topRadius * 2, height: notchSize.height)
        }
        return hasNotch ? CGSize(width: notchSize.width + topRadius * 2, height: notchSize.height) : .zero
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if expanded && !hasNotch && !showsCompact && nowPlaying.track == nil { return }
        isExpanded = expanded
        if expanded {
            nowPlaying.refreshPosition()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}
