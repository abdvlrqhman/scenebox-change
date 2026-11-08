//
//  PlaybackSettingsPanel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import SwiftUI
import SwiftVLC

struct PlaybackSettingsPanel: View {
    let player: Player
    let subs: SubtitlesController
    var onAudioSelected: (Track) -> Void = { _ in }
    /// Opened from the CC button: audio and subtitles (language, version, size, sync).
    var opensOnSubtitles = false
    /// Off when a separate CC button owns audio and subtitles, so the two buttons
    /// never open the same page (tvOS and casting have only one button).
    var includesTracks = true
    /// Opens this episode's other versions (closing the player): the way to a
    /// voice or language this file doesn't have.
    var onChooseVersion: (() -> Void)? = nil
    /// Phones only: the screen turns from here rather than from a top-bar icon.
    var onRotate: (() -> Void)? = nil
    let onClose: () -> Void

    private enum Page { case root, captions, subtitles, versions }
    @Environment(AppSettings.self) private var settings
    @State private var page: Page = .root
    /// Language whose versions are listed, and where Back returns to.
    @State private var versionsLanguage: String?
    @State private var versionsReturn: Page = .root

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack(alignment: opensOnSubtitles ? .center : .trailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case .root:
                        header(title: "Playback")
                        if includesTracks {
                            if uniqueTracks(player.audioTracks).count > 1 { audioSection }
                            subtitleNavSection
                            sizeSection           // tvOS has no CC page, so size lives here too
                            if hasActiveSubtitle { subtitleDelaySection }
                        }
                        speedSection
                        aspectSection
                        if let onRotate {
                            SettingsSection(title: "Screen") {
                                NavRow(title: "Rotate", value: "") {
                                    onClose()
                                    onRotate()
                                }
                            }
                        }
                    case .captions:
                        // Audio and subtitles side by side, each a list with a check, like
                        // every streaming app; stacked when there isn't room for two columns.
                        header(title: "Audio & subtitles")
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 32) {
                                audioColumn.frame(minWidth: 240, maxWidth: .infinity, alignment: .topLeading)
                                subtitleColumn.frame(minWidth: 300, maxWidth: .infinity, alignment: .topLeading)
                            }
                            VStack(alignment: .leading, spacing: 22) {
                                audioColumn
                                subtitleColumn
                            }
                        }
                    case .subtitles:
                        header(title: opensOnSubtitles ? "All languages" : "Subtitles")
                        subtitleSection
                    case .versions:
                        header(title: versionsTitle)
                        versionsSection
                        if hasActiveSubtitle { subtitleDelaySection }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: opensOnSubtitles ? 860 : panelWidth, maxHeight: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(panelInset)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.15), value: page)
        .onAppear {
            guard opensOnSubtitles else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { page = .captions }
        }
        #if os(tvOS)
        .onExitCommand {
            if page == home { onClose() } else { goBack() }
        }
        #endif
    }

    private func header(title: String) -> some View {
        HStack(spacing: 14) {
            if page != home {
                #if os(tvOS)
                Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(TVCircleButtonStyle(diameter: 46))
                    .accessibilityLabel("Back")
                #else
                Button { goBack() } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                #endif
            }
            Text(title)
                .font(.display(24, weight: .regular, relativeTo: .title2))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            if page == home {
                #if os(tvOS)
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(TVCircleButtonStyle(diameter: 46))
                    .accessibilityLabel("Close")
                #else
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                #endif
            }
        }
    }

    private var audioSection: some View {
        SettingsSection(title: "Audio") {
            ForEach(uniqueTracks(player.audioTracks)) { track in
                OptionRow(title: trackTitle(track), detail: trackDetail(track),
                          selected: player.selectedAudioTrack?.id == track.id) {
                    player.selectedAudioTrack = track
                    onAudioSelected(track)
                }
            }
        }
    }

    /// Every voice in this file, always shown (one voice says so), and the way to
    /// another version when the wanted language isn't here.
    private var audioColumn: some View {
        let tracks = uniqueTracks(player.audioTracks)
        return SettingsSection(title: "Audio") {
            if tracks.isEmpty {
                Text("Loading voices…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(minHeight: 44)
            }
            ForEach(tracks) { track in
                OptionRow(title: trackTitle(track), detail: trackDetail(track),
                          selected: player.selectedAudioTrack?.id == track.id || tracks.count == 1) {
                    player.selectedAudioTrack = track
                    onAudioSelected(track)
                }
            }
            if tracks.count == 1 {
                Text("This version has one voice.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let onChooseVersion {
                NavRow(title: "Other versions", value: "Other languages", action: onChooseVersion)
            }
        }
    }

    private var subtitleColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            subtitleQuickSection
            sizeSection
            if hasActiveSubtitle { subtitleDelaySection }
        }
    }

    /// "French": the language, not VLC's "Track 1 · fre"; its own name when it has none.
    private func trackTitle(_ track: Track) -> String {
        guard let code = track.language, !code.isEmpty else { return track.name }
        let name = SubtitleLanguage.displayName(for: SubtitleLanguage.canonical(code))
        return name.count <= 3 && name == name.uppercased() ? track.name : name   // unknown code
    }

    /// What tells two voices apart ("5.1", "Commentary"), without the language or "Track 2".
    private func trackDetail(_ track: Track) -> String? {
        let rest = track.name
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^track\s*\d+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–·"))
        guard !rest.isEmpty, rest.caseInsensitiveCompare(trackTitle(track)) != .orderedSame else { return nil }
        return rest
    }

    private var subtitleNavSection: some View {
        SettingsSection(title: "Subtitles") {
            NavRow(title: "Language", value: currentSubtitleLabel) { page = .subtitles }
            versionRow
        }
    }

    @ViewBuilder private var versionRow: some View {
        if let active = subs.selectedTrack,
           subs.versions(for: active.languageCode, player: player).count > 1 {
            NavRow(title: "Subtitle version", value: Self.versionName(active)) {
                showVersions(of: active.languageCode, returningTo: page)
            }
        }
    }

    /// Where Back ends up: the page the panel opened on.
    private var home: Page { opensOnSubtitles ? .captions : .root }

    private func goBack() {
        page = page == .versions ? versionsReturn : home
    }

    private static let sizes: [(name: String, spoken: String, scale: Double)] = [
        ("S", "Small", 0.75), ("M", "Medium", 1.0), ("L", "Large", 1.25), ("XL", "Extra large", 1.5),
    ]

    /// Subtitle size, applied at once (it used to wait for the next video).
    private var sizeSection: some View {
        SettingsSection(title: "Size") {
            HStack(spacing: 8) {
                ForEach(Self.sizes.indices, id: \.self) { index in
                    let size = Self.sizes[index]
                    let on = abs(settings.subtitleScale - size.scale) < 0.01
                    Button {
                        settings.subtitleScale = size.scale
                        player.setSubtitleScale(SubtitleScale(Float(size.scale)))
                    } label: {
                        Text(size.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Color.black : Color.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Color.white : Color.white.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(size.spoken)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func showVersions(of language: String, returningTo origin: Page) {
        versionsLanguage = language
        versionsReturn = origin
        page = .versions
    }

    private var versionsTitle: String {
        guard let versionsLanguage else { return "Versions" }
        return "\(SubtitleLanguage.displayName(for: versionsLanguage)) versions"
    }

    /// Every version in the chosen language, best first. Tapping switches right
    /// away and the panel stays open, so versions can be compared.
    private var versionsSection: some View {
        let list = versionsLanguage.map { subs.versions(for: $0, player: player) } ?? []
        let videoFPS = player.videoTracks.first?.frameRate
        return SettingsSection(title: "\(list.count) available") {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, track in
                VersionRow(title: Self.versionName(track, index: index),
                           tags: tags(for: track, index: index, videoFPS: videoFPS),
                           selected: subs.selectedID == track.id,
                           loading: subs.loadingID == track.id) {
                    subs.apply(track, on: player, exact: true)
                }
            }
            if let message = subs.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let versionsLanguage { translateRow(to: versionsLanguage) }
        }
    }

    /// "Translate English to Arabic": for when no version in the language fits.
    /// Shows where a translation stands, since it runs on after the player closes.
    @ViewBuilder
    private func translateRow(to language: String, onlyWhenNeeded: Bool = false) -> some View {
        #if canImport(Translation) && os(iOS)
        let state = subs.translationState(to: language, player: player)
        if subs.canTranslate(to: language, player: player),
           !onlyWhenNeeded || state != .none || subs.versions(for: language, player: player).isEmpty {
            let name = SubtitleLanguage.displayName(for: language)
            let running: Bool = { if case .running = state { return true } else { return false } }()
            Button {
                subs.translate(to: language, player: player)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "character.bubble")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: state, name: name))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(subs.translationError(to: language, player: player) ?? detail(for: state))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    if running { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    #if canImport(Translation) && os(iOS)
    private func title(for state: TranslationCenter.State, name: String) -> String {
        switch state {
        case .none: "Translate English to \(name)"
        case .running(let progress): "Translating… \(Int(progress * 100))%"
        case .paused(let progress): "Continue translating (\(Int(progress * 100))% done)"
        case .done: "Show the \(name) translation"
        }
    }

    private func detail(for state: TranslationCenter.State) -> String {
        switch state {
        case .none:
            "Made on this iPhone from the English subtitles, so it stays in sync."
        case .running:
            "Tap to show it now. Lines fill in as they're translated, and it keeps going if you close the player."
        case .paused:
            "It stopped part-way. The lines already translated are kept."
        case .done:
            "Translated on this iPhone."
        }
    }
    #endif

    private func tags(for track: SubtitleTrack, index: Int, videoFPS: Double?) -> [VersionRow.Tag] {
        var tags: [VersionRow.Tag] = []
        if index == 0 { tags.append(.init(text: "Best match", tone: .accent)) }
        if let fps = track.fps {
            let label = String(format: "%.5g fps", fps)   // 23.976, 25, 29.97
            if let videoFPS, videoFPS > 1 {
                if abs(fps - videoFPS) < 0.05 {
                    tags.append(.init(text: "\(label), same as video", tone: .good))
                } else if subs.frameRateScale(for: track) != 1 {
                    tags.append(.init(text: "\(label), corrected", tone: .good))
                } else if abs(fps - videoFPS) > 0.3 {
                    tags.append(.init(text: "\(label), may drift", tone: .warn))
                } else {
                    tags.append(.init(text: label, tone: .plain))
                }
            } else {
                tags.append(.init(text: label, tone: .plain))
            }
        }
        if track.id.hasPrefix(TranslatedSubtitles.idPrefix) {
            switch TranslationCenter.shared.state(for: track.id) {
            case .running(let progress):
                tags.append(.init(text: "Translating \(Int(progress * 100))%", tone: .accent))
            case .paused(let progress):
                tags.append(.init(text: "\(Int(progress * 100))% translated", tone: .warn))
            default:
                break
            }
        }
        if track.isMachineTranslated { tags.append(.init(text: "Machine translated", tone: .warn)) }
        if track.isHearingImpaired { tags.append(.init(text: "SDH", tone: .plain)) }
        tags.append(.init(text: track.provider, tone: .plain))
        if track.downloads >= 1000 {
            tags.append(.init(text: "\(track.downloads / 1000)k downloads", tone: .plain))
        }
        if subs.lastKeptID == track.id, subs.selectedID != track.id {
            tags.append(.init(text: "Kept last time", tone: .plain))
        }
        if let offset = subs.savedOffset(for: track), offset != 0 {
            tags.append(.init(text: String(format: "Sync %+.2f s", Double(offset) / 1000), tone: .plain))
        }
        return tags
    }

    /// "Breaking.Bad.S01E01.720p.HDTV.x264-BiA.srt" → "Breaking Bad S01E01 720p HDTV x264-BiA".
    static func versionName(_ track: SubtitleTrack, index: Int? = nil) -> String {
        guard var name = track.fileName, !name.isEmpty else {
            return index.map { "Version \($0 + 1)" } ?? "Selected version"
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if ["srt", "vtt", "ass", "ssa", "sub"].contains(ext) { name = (name as NSString).deletingPathExtension }
        return name.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    private var subtitleSection: some View {
        SettingsSection(title: "Languages") {
            OptionRow(title: "Off", selected: !hasActiveSubtitle) {
                subs.apply(nil, on: player)
                page = home
            }

            ForEach(subs.embeddedTracks(of: player)) { track in
                OptionRow(title: trackTitle(track), detail: trackDetail(track),
                          selected: subs.embeddedID == track.id) {
                    subs.selectEmbedded(track, on: player)
                    page = home
                }
            }

            if subs.isLoading {
                Label("Loading…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let message = subs.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sortedLanguages, id: \.language) { group in languageRow(group) }
            // Always reachable, including when the default language has no
            // versions at all.
            let defaultLanguage = settings.preferredSubtitleLanguage
            if !defaultLanguage.isEmpty { translateRow(to: defaultLanguage) }
        }
    }

    /// The CC page's list: Off, the languages worth one tap, what's built into
    /// the video, then "More languages" for the rest.
    private var subtitleQuickSection: some View {
        let pinned = pinnedLanguages
        let others = subs.byLanguage.count - pinned.count
        return SettingsSection(title: "Subtitles") {
            OptionRow(title: "Off", selected: !hasActiveSubtitle) { subs.apply(nil, on: player) }
            ForEach(pinned, id: \.language) { group in languageRow(group) }
            ForEach(subs.embeddedTracks(of: player)) { track in
                OptionRow(title: trackTitle(track),
                          detail: [trackDetail(track), "In the video"].compactMap { $0 }.joined(separator: ", "),
                          selected: subs.embeddedID == track.id) {
                    subs.selectEmbedded(track, on: player)
                }
            }
            if subs.isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Finding subtitles…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(minHeight: 44)
            } else if let message = subs.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if others > 0 {
                NavRow(title: "More languages", value: "\(others)") { page = .subtitles }
            }
            let defaultLanguage = settings.preferredSubtitleLanguage
            if !defaultLanguage.isEmpty { translateRow(to: defaultLanguage, onlyWhenNeeded: true) }
        }
    }

    /// The viewer's language, the one showing, then English; each once, in that order.
    private var pinnedLanguages: [(language: String, tracks: [SubtitleTrack])] {
        let preferred = SubtitleLanguage.canonical(settings.preferredSubtitleLanguage)
        let showing = subs.selectedTrack.map { SubtitleLanguage.canonical($0.languageCode) }
        var seen = Set<String>()
        return [preferred, showing, "eng"].compactMap { code in
            guard let code, !code.isEmpty, seen.insert(code).inserted else { return nil }
            return subs.byLanguage.first { group in
                group.tracks.first.map { SubtitleLanguage.canonical($0.languageCode) } == code
            }
        }
    }

    /// Pinned languages first, the rest A to Z.
    private var sortedLanguages: [(language: String, tracks: [SubtitleTrack])] {
        let pinned = pinnedLanguages
        let pinnedNames = Set(pinned.map(\.language))
        return pinned + subs.byLanguage
            .filter { !pinnedNames.contains($0.language) }
            .sorted { $0.language.localizedStandardCompare($1.language) == .orderedAscending }
    }

    /// Tapping the language shows its best version; "12 versions" opens the list
    /// to try another, so choosing never jumps pages by surprise.
    @ViewBuilder
    private func languageRow(_ group: (language: String, tracks: [SubtitleTrack])) -> some View {
        if let code = group.tracks.first?.languageCode {
            let count = group.tracks.count
            let active = group.tracks.contains { $0.id == subs.selectedID }
            #if os(tvOS)
            OptionRow(title: count > 1 ? "\(group.language), \(count) versions" : group.language,
                      selected: active) {
                if !active, let best = subs.versions(for: code, player: player).first {
                    subs.apply(best, on: player)
                }
                if count > 1 { showVersions(of: code, returningTo: page) }
            }
            #else
            HStack(spacing: 4) {
                OptionRow(title: group.language, selected: active) {
                    if !active, let best = subs.versions(for: code, player: player).first {
                        subs.apply(best, on: player)
                    }
                }
                if count > 1 {
                    Button { showVersions(of: code, returningTo: page) } label: {
                        HStack(spacing: 4) {
                            Text("\(count) versions")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(minHeight: 44)
                        .padding(.leading, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(count) \(group.language) versions")
                }
            }
            #endif
        }
    }

    private var currentSubtitleLabel: String {
        if let id = subs.embeddedID,
           let track = subs.embeddedTracks(of: player).first(where: { $0.id == id }) {
            return trackTitle(track)
        }
        if let group = subs.byLanguage.first(where: { group in
            group.tracks.contains { $0.id == subs.selectedID }
        }) {
            return group.language
        }
        return "Off"
    }

    private var subtitleDelaySection: some View {
        SettingsSection(title: "Subtitle sync") {
            HStack(spacing: 12) {
                syncStep(-1, label: "−1s")
                Button { adjustSubtitleDelay(by: -0.25) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Subtitles earlier by a quarter second")

                VStack(spacing: 2) {
                    Text(delayText).font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                    if abs(delaySeconds) >= 0.01 {
                        Button("Reset to 0") { setSubtitleDelay(milliseconds: 0) }
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .buttonStyle(.plain)
                    } else {
                        Text(delayHint).font(.caption2).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity)

                Button { adjustSubtitleDelay(by: 0.25) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Subtitles later by a quarter second")
                syncStep(1, label: "+1s")
            }
            Text("Minus shows subtitles earlier, plus later. Saved for this version.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func syncStep(_ seconds: Double, label: String) -> some View {
        Button { adjustSubtitleDelay(by: seconds) } label: {
            Text(label)
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Subtitles one second earlier" : "Subtitles one second later")
    }

    private var speedSection: some View {
        SettingsSection(title: "Speed") {
            ForEach(rates, id: \.self) { rate in
                OptionRow(title: String(format: "%.2g×", rate),
                          selected: abs(player.rate - rate) < 0.01) {
                    try? player.setPlaybackRate(PlaybackRate(rate))
                    PlayerChoices.rate = rate
                }
            }
        }
    }

    private var aspectSection: some View {
        SettingsSection(title: "Aspect ratio") {
            aspectRow("Fit", .default)
            aspectRow("Fill", .fill)
            aspectRow("16:9", .ratio(16, 9))
            aspectRow("4:3", .ratio(4, 3))
        }
    }

    private func aspectRow(_ title: String, _ ratio: AspectRatio) -> some View {
        OptionRow(title: title, selected: player.aspectRatio == ratio) {
            player.aspectRatio = ratio
            PlayerChoices.aspect = ratio
        }
    }

    private func uniqueTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private var hasActiveSubtitle: Bool {
        subs.embeddedID != nil || subs.selectedID != nil
    }

    /// Sync lives in the subtitle controller: baked into external versions,
    /// VLC's delay for tracks inside the video.
    private var delaySeconds: Double { Double(subs.offsetMilliseconds) / 1000 }

    private var delayText: String { String(format: "%+.2f s", delaySeconds) }

    private var delayHint: String {
        if abs(delaySeconds) < 0.01 { return "in sync" }
        return delaySeconds > 0 ? "later" : "earlier"
    }

    private func adjustSubtitleDelay(by seconds: Double) {
        setSubtitleDelay(milliseconds: Int(((delaySeconds + seconds) * 1000).rounded()))
    }

    private func setSubtitleDelay(milliseconds: Int) {
        subs.setOffset(milliseconds)
    }

    #if os(tvOS)
    private var panelWidth: CGFloat { 560 }
    private var panelInset: CGFloat { 48 }
    #else
    private var panelWidth: CGFloat { 360 }
    private var panelInset: CGFloat { 12 }
    #endif
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                #if os(tvOS)
                .padding(.leading, 16)   // line the header up with the row text inset
                #endif
            content
        }
    }
}

struct OptionRow: View {
    let title: String
    /// Quiet text before the checkmark ("In the video").
    var detail: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        Button(action: action) { Text(title).lineLimit(1) }
            .buttonStyle(OptionRowStyle(selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
        #else
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        #endif
    }
}

/// One subtitle version: its release name and a few facts that help choose.
struct VersionRow: View {
    struct Tag: Hashable {
        enum Tone { case accent, good, warn, plain }
        let text: String
        let tone: Tone
    }

    let title: String
    let tags: [Tag]
    let selected: Bool
    let loading: Bool
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).lineLimit(2)
                if !tags.isEmpty {
                    Text(tags.map(\.text).joined(separator: ", "))
                        .font(.callout)
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(OptionRowStyle(selected: selected))
        #else
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag.text)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(color(tag.tone))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(color(tag.tone).opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
                Spacer(minLength: 6)
                Group {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else if selected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        #endif
    }

    private func color(_ tone: Tag.Tone) -> Color {
        switch tone {
        case .accent: Theme.accent
        case .good: Theme.success
        case .warn: Theme.warning
        case .plain: .white.opacity(0.7)
        }
    }
}

struct NavRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).lineLimit(1).opacity(0.6)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .opacity(0.6)
            }
        }
        .buttonStyle(NavRowStyle())
        #else
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer(minLength: 8)
                Text(value)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.55))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #endif
    }
}

#if os(tvOS)
private struct NavRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    struct Row: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.title3)
                .foregroundStyle(isFocused ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(isFocused ? Color.white : .clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(isFocused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

private struct OptionRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }

    struct Row: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: 12) {
                configuration.label
                    .font(.title3)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(isFocused ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(isFocused ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var rowBackground: Color {
            if isFocused { return .white }
            return selected ? .white.opacity(0.1) : .clear
        }
    }
}
#endif
