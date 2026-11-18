import Foundation

enum SettingsKey {
    static let mediaSource = "mediaSource"
    static let showsMedia = "showsMedia"
    static let islandStyle = "islandStyle"
    static let showsEmber = "showsEmber"
    static let lockScreen = "lockScreenLyrics"
    static let lockScreenBackdrop = "lockScreenBackdrop"
    static let lockScreenClock = "lockScreenClock"
    static let lockScreenBattery = "lockScreenBattery"
    static let wordByWord = "wordByWord"
    static let hasWelcomed = "hasWelcomed"
}

enum SourcePreference: String, CaseIterable, Identifiable {
    case automatic, spotify, music

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    var source: MediaSource? {
        switch self {
        case .automatic: nil
        case .spotify: .spotify
        case .music: .music
        }
    }

    static var current: SourcePreference {
        UserDefaults.standard.string(forKey: SettingsKey.mediaSource).flatMap(SourcePreference.init(rawValue:)) ?? .automatic
    }
}

enum IslandStyle: String, CaseIterable, Identifiable {
    case solid, glass

    var id: Self { self }

    var title: String {
        switch self {
        case .solid: "Solid"
        case .glass: "Glass"
        }
    }
}

extension UserDefaults {
    func bool(forKey key: String, default fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }
}
