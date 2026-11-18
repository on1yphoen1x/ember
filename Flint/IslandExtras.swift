import AppKit
import SwiftUI

/// Frosted glass that blurs whatever is behind the island. The strip beside the
/// camera stays black so the hardware notch still blends in.
struct GlassFill: View {
    let headerHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            BehindWindowBlur()
            Color.black.opacity(0.28)
            LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0), location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: headerHeight + 18)
        }
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct WelcomeView: View {
    @ObservedObject var model: IslandModel
    @State private var shine = false

    var body: some View {
        VStack(spacing: 6) {
            Text("Flint")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1, green: 0.62, blue: 0.25), .white, Color(red: 1, green: 0.78, blue: 0.45)],
                        startPoint: shine ? .leading : .trailing,
                        endPoint: shine ? .trailing : .leading
                    )
                )
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: shine)
            Text("Music, files and recordings, right at the notch.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { model.finishWelcome() }
                MainWindowOpener.open()
            } label: {
                Text("Get Started")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { shine = true }
    }
}

/// Lets AppKit code reach SwiftUI's openWindow, which only exists inside scenes.
@MainActor
enum MainWindowOpener {
    static var action: (() -> Void)?

    static func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            action?()
        }
    }
}
