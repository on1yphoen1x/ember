import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject var shelf: Shelf
    let isTargeted: Bool

    var body: some View {
        Group {
            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                    Text(shelf.isAdding ? "Adding..." : "Drop files here to keep them in the notch")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(isTargeted ? 0.6 : 0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
            } else {
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(shelf.items, id: \.self) { url in
                                ShelfTile(url: url, shelf: shelf)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(isTargeted ? 0.1 : 0))
                    }

                    VStack(spacing: 8) {
                        ShelfButton(symbol: "airplayaudio", help: "AirDrop everything") {
                            shelf.airDrop(shelf.items)
                        }
                        ShelfButton(symbol: "trash", help: "Clear the shelf") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { shelf.clear() }
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: shelf.items)
    }
}

struct ShelfTile: View {
    let url: URL
    @ObservedObject var shelf: Shelf
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72, height: 26, alignment: .top)
        }
        .padding(6)
        .background(.white.opacity(isHovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { shelf.remove(url) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.reveal(url) }
            Button("AirDrop") { shelf.airDrop([url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.lastPathComponent)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct ShelfButton: View {
    let symbol: String
    let help: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
    }
}
