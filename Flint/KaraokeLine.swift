import SwiftUI

/// Lights up a lyric line word by word.
///
/// LRCLIB only times whole lines, so each word gets a share of the line's
/// duration in proportion to its length. Long words take longer to sing, which
/// keeps the estimate close enough to feel in time.
struct KaraokeLine: View {
    let text: String
    let start: Double
    let end: Double
    let position: Double
    var dimOpacity: Double = 0.35

    var body: some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let weights = words.map { Double(max($0.count, 2)) }
        let total = weights.reduce(0, +)
        // Lines are usually sung a little faster than the gap to the next one.
        let span = max((end - start) * 0.85, 0.4)
        let progress = min(max((position - start) / span, 0), 1) * total

        var spent = 0.0
        var line = Text("")
        for (index, word) in words.enumerated() {
            let lit = min(max((progress - spent) / weights[index], 0), 1)
            spent += weights[index]
            let separator = index == words.count - 1 ? "" : " "
            line = line + Text(word + separator).foregroundColor(.white.opacity(dimOpacity + (1 - dimOpacity) * lit))
        }
        return line
    }
}
