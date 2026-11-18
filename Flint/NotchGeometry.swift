import AppKit

extension NSScreen {
    /// The camera housing in screen coordinates, or nil on displays without one.
    var notchRect: CGRect? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return nil }
        let width = frame.width - left.width - right.width
        guard width > 0 else { return nil }
        let height = safeAreaInsets.top
        return CGRect(x: frame.minX + left.width, y: frame.maxY - height, width: width, height: height)
    }

    var menuBarHeight: CGFloat {
        let height = frame.maxY - visibleFrame.maxY
        return height > 0 ? height : 24
    }

    /// The built-in display when it has a notch, because that is where the island belongs
    /// even when an external monitor is the main screen.
    static var islandScreen: NSScreen? {
        screens.first { $0.notchRect != nil } ?? main
    }
}
