//
//  TranslationUnits.swift
//  SceneBox
//

import Foundation

/// A sentence as the translator should see it. Subtitles cut sentences to fit
/// the screen ("I think we" / "should leave now."), and a translator given the
/// halves separately gets the grammar and meaning wrong. Split lines are
/// joined here, translated whole, then spread back over the original timings.
nonisolated struct TranslationUnit: Sendable, Codable, Hashable {
    let cues: [Int]         // positions in the cue list, in order
    let parts: [String]     // each cue's text, one line each

    var text: String { parts.joined(separator: " ") }
    var weights: [Int] { parts.map { max(1, $0.count) } }
}

nonisolated enum TranslationUnits {
    /// Joins consecutive cues into sentences: a cue continues the previous one
    /// unless that one ended a sentence, a new speaker starts ("- "), there is
    /// a pause of more than 1.5 s, or four cues are already joined.
    static func build(_ cues: [SubtitleCue]) -> [TranslationUnit] {
        var units: [TranslationUnit] = []
        var current: [(index: Int, text: String)] = []
        var lastEnd = Int.min

        func flush() {
            guard !current.isEmpty else { return }
            units.append(TranslationUnit(cues: current.map(\.index), parts: current.map(\.text)))
            current.removeAll()
        }

        for (index, cue) in cues.enumerated() {
            let raw = cue.plainText
            guard !raw.isEmpty else { continue }
            // Two speakers in one cue ("- Hi.\n- Hello.") keep their lines.
            let isDialogue = raw.hasPrefix("-") || raw.contains("\n-")
            let text = isDialogue ? raw : raw.replacingOccurrences(of: "\n", with: " ")
            if let previous = current.last {
                let pause = lastEnd == Int.min ? 0 : cue.startMilliseconds - lastEnd
                if isDialogue || endsSentence(previous.text) || pause > 1500 || current.count >= 4 {
                    flush()
                }
            }
            current.append((index, text))
            if isDialogue { flush() }
            lastEnd = cue.endMilliseconds
        }
        flush()
        return units
    }

    static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        return ".!?…♪\"'»)]:".contains(last)
    }

    /// Spreads a translated sentence back over its cues, word by word, in
    /// proportion to how long each original piece was.
    static func split(_ translated: String, weights: [Int]) -> [String] {
        guard weights.count > 1 else { return [translated] }
        let words = translated.split(whereSeparator: \.isWhitespace).map(String.init)
        // Too few words to go round: show the whole line for the span.
        guard words.count >= weights.count else { return Array(repeating: translated, count: weights.count) }

        let totalWeight = Double(weights.reduce(0, +))
        let totalChars = Double(words.reduce(0) { $0 + $1.count + 1 })
        var parts: [String] = []
        var index = 0
        var usedChars = 0.0
        var usedWeight = 0.0
        for (slot, weight) in weights.enumerated() {
            let remainingSlots = weights.count - slot - 1
            if remainingSlots == 0 {
                parts.append(words[index...].joined(separator: " "))
                break
            }
            usedWeight += Double(weight)
            let target = totalChars * usedWeight / totalWeight
            var taken: [String] = []
            // Take at least one word, stop near the target, and leave one per later slot.
            while index < words.count - remainingSlots,
                  taken.isEmpty || usedChars + Double(words[index].count + 1) / 2 <= target {
                taken.append(words[index])
                usedChars += Double(words[index].count + 1)
                index += 1
            }
            parts.append(taken.joined(separator: " "))
        }
        return parts
    }
}
