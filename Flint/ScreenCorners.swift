import AppKit
import SwiftUI

/// Rounds the bottom corners of every display so they match the curved top.
@MainActor
final class ScreenCorners {
    static let radius: CGFloat = 10

    private var windows: [NSWindow] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        update()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.roundedCorners, default: true)
    }

    private func update() {
        let wanted = isEnabled ? NSScreen.screens.count * 2 : 0
        guard wanted != windows.count || !isEnabled else {
            layout()
            return
        }
        windows.forEach { $0.orderOut(nil) }
        windows = (0..<wanted).map { index in makeWindow(isLeft: index.isMultiple(of: 2)) }
        layout()
    }

    private func layout() {
        let size = Self.radius
        for (index, screen) in NSScreen.screens.enumerated() where windows.count > index * 2 + 1 {
            let frame = screen.frame
            windows[index * 2].setFrame(CGRect(x: frame.minX, y: frame.minY, width: size, height: size), display: true)
            windows[index * 2 + 1].setFrame(CGRect(x: frame.maxX - size, y: frame.minY, width: size, height: size), display: true)
        }
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func makeWindow(isLeft: Bool) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: CornerShape(isLeft: isLeft).fill(.black))
        host.sizingOptions = []
        window.contentView = host
        return window
    }
}

/// The black wedge left over when a square corner is rounded off.
private struct CornerShape: Shape {
    let isLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner = CGPoint(x: isLeft ? rect.minX : rect.maxX, y: rect.maxY)
        let alongBottom = CGPoint(x: isLeft ? rect.maxX : rect.minX, y: rect.maxY)
        let upSide = CGPoint(x: corner.x, y: rect.minY)
        path.move(to: corner)
        path.addLine(to: upSide)
        path.addQuadCurve(to: alongBottom, control: corner)
        path.closeSubpath()
        return path
    }
}
