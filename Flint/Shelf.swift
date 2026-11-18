import AppKit

/// Files dropped on the notch. They're kept in Flint's own folder so they stay
/// available even if the original is moved or deleted.
@MainActor
final class Shelf: ObservableObject {
    @Published private(set) var items: [URL] = []
    @Published private(set) var isAdding = false

    private let folder: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("Flint/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    func add(_ urls: [URL]) {
        let files = urls.filter { $0.isFileURL && $0.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL }
        guard !files.isEmpty else { return }
        isAdding = true
        let folder = folder
        Task {
            await Task.detached(priority: .userInitiated) {
                for file in files {
                    let target = Self.freeName(for: file.lastPathComponent, in: folder)
                    // A hard link is instant and takes no extra space; copying is the
                    // fallback for other volumes and for folders.
                    do {
                        try FileManager.default.linkItem(at: file, to: target)
                    } catch {
                        try? FileManager.default.copyItem(at: file, to: target)
                    }
                }
            }.value
            isAdding = false
            reload()
        }
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    func clear() {
        items.forEach { try? FileManager.default.removeItem(at: $0) }
        reload()
    }

    func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.addedToDirectoryDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        items = contents.sorted { added($0) < added($1) }
    }

    private func added(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .distantPast
    }

    private nonisolated static func freeName(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            number += 1
        }
        return candidate
    }
}
