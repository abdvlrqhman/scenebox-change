//
//  TranslationCenter.swift
//  SceneBox
//

import Foundation
import Observation
#if canImport(Translation) && os(iOS)
@preconcurrency import Translation
#endif

/// Saved progress of one translation, so it survives closing the player or
/// the app and continues where it stopped.
nonisolated struct TranslationWork: Codable, Sendable {
    let id: String                  // the translated version's id
    let english: SubtitleTrack
    let target: String
    let cues: [SubtitleCue]         // the English subtitles
    let units: [TranslationUnit]
    var done: [Int: [String]] = [:] // unit → translated text per cue

    var progress: Double { units.isEmpty ? 1 : Double(done.count) / Double(units.count) }
    var isComplete: Bool { done.count >= units.count }

    /// Translated lines where ready, English elsewhere.
    func cuesSoFar() -> [SubtitleCue] {
        var out = cues
        for (unit, parts) in done where unit < units.count {
            for (offset, index) in units[unit].cues.enumerated() where offset < parts.count && index < out.count {
                out[index].text = parts[offset]
            }
        }
        return out
    }
}

/// Runs subtitle translations for the whole app.
///
/// Translation used to belong to the player screen, so closing the player cut
/// it off halfway. Here it keeps going while the viewer browses, saves its
/// progress as it goes, and is only marked finished when every line is done.
@MainActor
@Observable
final class TranslationCenter {
    static let shared = TranslationCenter()

    enum State: Equatable {
        case none
        case running(Double)
        case paused(Double)     // stopped part-way; can continue
        case done
    }

    /// The newest file for a translation, for players showing it.
    struct Update: Equatable {
        let url: URL
        let isFinal: Bool
        let revision: Int
    }

    private(set) var updates: [String: Update] = [:]
    private(set) var runningID: String?
    private(set) var runningProgress: Double = 0
    private(set) var lastError: [String: String] = [:]

    @ObservationIgnored private var queue: [(id: String, code: String, startAt: Int)] = []
    @ObservationIgnored private var work: TranslationWork?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var lastPublishedProgress = 0.0

    private init() {}

    func state(for id: String) -> State {
        if TranslatedSubtitles.cached(id: id) != nil { return .done }
        if runningID == id { return .running(runningProgress) }
        if queue.contains(where: { $0.id == id }) { return .running(0) }
        if let saved = Self.loadWork(id: id) { return .paused(saved.progress) }
        return .none
    }

    /// The translation running now, for a player of the same episode to list.
    var runningJob: (id: String, english: SubtitleTrack, target: String)? {
        guard let work, work.id == runningID else { return nil }
        return (work.id, work.english, work.target)
    }

    /// The best file there is right now: finished, or what's translated so far.
    func currentFile(for id: String) -> URL? {
        if let update = updates[id] { return update.url }
        if let cached = TranslatedSubtitles.cached(id: id) { return cached.file }
        guard let saved = Self.loadWork(id: id), !saved.done.isEmpty else { return nil }
        return try? TranslatedSubtitles.writePartial(saved.cuesSoFar(), id: id)
    }

    /// Starts (or continues) translating `english` into `target`, from the
    /// line at `startAt` milliseconds so the viewer's next minutes come first.
    func enqueue(english: SubtitleTrack, file: URL, target: String, code: String, startAt: Int) {
        let id = TranslatedSubtitles.id(englishID: english.id, target: target)
        lastError[id] = nil
        guard TranslatedSubtitles.cached(id: id) == nil, runningID != id,
              !queue.contains(where: { $0.id == id }) else { return }
        if Self.loadWork(id: id) == nil {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                lastError[id] = "The English subtitles couldn't be read."
                return
            }
            let cues = SubtitleCues.parse(text)
            guard !cues.isEmpty else {
                lastError[id] = "The English subtitles are empty."
                return
            }
            Self.saveWork(TranslationWork(id: id, english: english, target: target,
                                          cues: cues, units: TranslationUnits.build(cues)))
        }
        queue.append((id, code, startAt))
        startNext()
    }

    /// Stops everything now (Clear cache): the running translation ends at its
    /// next result and writes nothing, so cleared files don't come back.
    func cancelAll() {
        runToken += 1
        queue.removeAll()
        runningID = nil
        runningProgress = 0
        work = nil
        updates.removeAll()
        lastError.removeAll()
        #if canImport(Translation) && os(iOS)
        textTargets = []
        configuration = nil
        #endif
    }

    /// Changes on cancelAll(); a run that sees a different value stops.
    @ObservationIgnored private var runToken = 0

    private func startNext() {
        guard runningID == nil, let next = queue.first else { return }
        queue.removeFirst()
        runningID = next.id
        runningProgress = Self.loadWork(id: next.id)?.progress ?? 0
        pendingStart = next.startAt
        #if canImport(Translation) && os(iOS)
        // A configuration equal to the last one wouldn't re-run the task;
        // invalidate() bumps it so back-to-back jobs always start.
        let target = Locale.Language(identifier: next.code)
        if var reused = lastConfiguration, reused.target == target {
            reused.invalidate()
            lastConfiguration = reused
        } else {
            lastConfiguration = TranslationSession.Configuration(source: Locale.Language(identifier: "en"),
                                                                 target: target)
        }
        configuration = lastConfiguration
        #endif
    }

    @ObservationIgnored private var pendingStart = 0

    // MARK: Running

    #if canImport(Translation) && os(iOS)
    /// Watched by `.translationTask` at the root of the app.
    private(set) var configuration: TranslationSession.Configuration?
    @ObservationIgnored private var lastConfiguration: TranslationSession.Configuration?

    func run(_ session: TranslationSession) async {
        let token = runToken
        guard let id = runningID, let current = Self.loadWork(id: id) else { finishRun(); return }
        work = current
        lastPublishedProgress = current.progress

        // Unfinished sentences, from the viewer's position onwards, then the rest.
        let firstUnit = current.units.firstIndex { unit in
            guard let cue = unit.cues.first, cue < current.cues.count else { return false }
            return current.cues[cue].startMilliseconds >= pendingStart - 5000
        } ?? 0
        let order = (Array(firstUnit..<current.units.count) + Array(0..<firstUnit))
            .filter { current.done[$0] == nil }

        // The same sentence ("Yeah.", "What?") is translated once.
        var texts: [String] = []
        var unitsForText: [[Int]] = []
        var slot: [String: Int] = [:]
        for unit in order {
            let text = current.units[unit].text
            if let existing = slot[text] {
                unitsForText[existing].append(unit)
            } else {
                slot[text] = texts.count
                texts.append(text)
                unitsForText.append([unit])
            }
        }
        textTargets = unitsForText

        do {
            if !texts.isEmpty {
                try await Self.translateStreaming(texts, with: session) { [weak self] results in
                    self?.apply(results, token: token) ?? false
                }
            }
            guard token == runToken else { return }            // cleared: write nothing
            guard let finished = work, finished.id == id else { finishRun(); return }
            if finished.isComplete {
                let english = finished.english
                let track = TranslatedSubtitles.track(from: english, target: finished.target, url: english.url)
                _ = try TranslatedSubtitles.write(finished.cuesSoFar(), track: track)
                Self.deleteWork(id: id)
                TranslatedSubtitles.removePartials(id: id)
                if let saved = TranslatedSubtitles.cached(id: id) {
                    revision += 1
                    updates[id] = Update(url: saved.file, isFinal: true, revision: revision)
                }
            } else {
                // The stream ended early (the app went to the background, most
                // likely): keep what's done for next time.
                Self.saveWork(finished)
                lastError[id] = "Translation paused. Tap Continue to finish it."
            }
        } catch {
            guard token == runToken else { return }
            if let partial = work { Self.saveWork(partial) }
            lastError[id] = "Translation paused. If iOS asked to download the language, allow it and tap Continue."
        }
        finishRun()
    }

    /// Each result fills every sentence with that text, then saves and shows
    /// progress now and then.
    /// Returns false when the run was cancelled, which stops the stream.
    private func apply(_ results: [(Int, String)], token: Int) -> Bool {
        guard token == runToken, var current = work else { return false }
        for (slot, translated) in results where slot < textTargets.count {
            for unit in textTargets[slot] where unit < current.units.count {
                current.done[unit] = TranslationUnits.split(translated, weights: current.units[unit].weights)
            }
        }
        work = current
        runningProgress = current.progress

        if Date().timeIntervalSince(lastSave) > 3 {
            lastSave = Date()
            Self.saveWork(current)
        }
        // The lines at the playhead go on screen within seconds (they're
        // translated first), then the file is refreshed every fifth, so a
        // viewer already watching sees more of it translated.
        let firstBatchReady = lastPublishedProgress == 0 && current.done.count >= min(12, current.units.count)
        if firstBatchReady || current.progress - lastPublishedProgress >= 0.2 {
            lastPublishedProgress = current.progress
            if let url = try? TranslatedSubtitles.writePartial(current.cuesSoFar(), id: current.id) {
                revision += 1
                updates[current.id] = Update(url: url, isFinal: false, revision: revision)
            }
        }
        return true
    }

    @ObservationIgnored private var textTargets: [[Int]] = []

    private func finishRun() {
        runningID = nil
        work = nil
        textTargets = []
        configuration = nil
        startNext()
    }

    /// Streams results: Apple's `translate(batch:)` hands back each sentence
    /// as it's ready. Only plain strings cross back to the main actor.
    nonisolated private static func translateStreaming(
        _ texts: [String], with session: TranslationSession,
        onResults: @escaping @MainActor ([(Int, String)]) -> Bool
    ) async throws {
        let requests = texts.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        var buffer: [(Int, String)] = []
        var lastFlush = Date()
        for try await response in session.translate(batch: requests) {
            if let id = response.clientIdentifier, let index = Int(id) {
                buffer.append((index, response.targetText))
            }
            if buffer.count >= 25 || Date().timeIntervalSince(lastFlush) > 0.4 {
                let flushed = buffer
                buffer.removeAll()
                lastFlush = Date()
                guard await onResults(flushed) else { return }     // cancelled
            }
        }
        if !buffer.isEmpty { _ = await onResults(buffer) }
    }
    #else
    private func finishRun() {
        runningID = nil
        work = nil
        startNext()
    }
    #endif

    // MARK: Saved progress

    nonisolated private static func workURL(id: String) -> URL {
        TranslatedSubtitles.workDirectory.appendingPathComponent(TranslatedSubtitles.digest(id) + ".work.json")
    }

    nonisolated static func loadWork(id: String) -> TranslationWork? {
        guard let data = try? Data(contentsOf: workURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(TranslationWork.self, from: data)
    }

    nonisolated static func saveWork(_ work: TranslationWork) {
        try? FileManager.default.createDirectory(at: TranslatedSubtitles.workDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(work) {
            try? data.write(to: workURL(id: work.id), options: .atomic)
        }
    }

    nonisolated static func deleteWork(id: String) {
        try? FileManager.default.removeItem(at: workURL(id: id))
    }
}
