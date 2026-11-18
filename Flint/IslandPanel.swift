import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IslandController {
    /// Big enough for the expanded island plus its shadow, so the window never has to resize mid-animation.
    private static let panelSize = CGSize(width: 680, height: 260)

    private let model: IslandModel
    private let panel: IslandPanel
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var hoverTask: Task<Void, Never>?
    private var isPointerInside = false
    private var anchorX: CGFloat = 0
    private var dragChangeCount = 0
    private var isFileDragging = false
    private var screenTop: CGFloat = 0

    init(model: IslandModel) {
        self.model = model
        panel = IslandPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize))

        let host = IslandHostingView(rootView: IslandView(model: model, nowPlaying: model.nowPlaying, ember: model.ember, shelf: model.shelf))
        host.sizingOptions = []
        panel.contentView = host

        layout()
        panel.orderFrontRegardless()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }

        // Global monitors see movement over other apps; the local one takes over once
        // the panel starts accepting clicks and the events are delivered to us instead.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            // Only drags carrying files open the shelf; dragging a window past the notch shouldn't.
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != dragChangeCount,
                  pasteboard.types?.contains(.fileURL) == true else { return }
            isFileDragging = true
            pointerMoved()
        case .leftMouseUp:
            isFileDragging = false
            pointerMoved()
        default:
            pointerMoved()
        }
    }

    private func layout() {
        guard let screen = NSScreen.islandScreen else { return }
        if let notch = screen.notchRect {
            model.hasNotch = true
            model.notchSize = notch.size
            anchorX = notch.midX
        } else {
            model.hasNotch = false
            model.notchSize = CGSize(width: 0, height: screen.menuBarHeight)
            anchorX = screen.frame.midX
        }
        screenTop = screen.frame.maxY
        let size = Self.panelSize
        panel.setFrame(
            CGRect(x: anchorX - size.width / 2, y: screenTop - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    private var hotRect: CGRect {
        var size = model.size
        if isFileDragging {
            // A generous target while carrying files, even when the island is hidden.
            size.width = max(size.width, model.notchSize.width + 160)
            size.height = max(size.height, model.notchSize.height + 30)
        }
        guard size != .zero else { return .null }
        return CGRect(x: anchorX - size.width / 2, y: screenTop - size.height, width: size.width, height: size.height)
            .insetBy(dx: -4, dy: -4)
    }

    private func pointerMoved() {
        let inside = hotRect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        guard inside != isPointerInside else { return }
        isPointerInside = inside

        let carryingFiles = isFileDragging
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(inside ? (carryingFiles ? 40 : 110) : 280))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                self.model.setExpanded(inside, for: inside && carryingFiles ? .shelf : nil)
            }
            if !inside { self.panel.ignoresMouseEvents = true }
        }
    }
}
