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
    var onAudioSelected: () -> Void = {}
    let onClose: () -> Void

    private enum Page { case root, subtitles, versions }
    @State private var page: Page = .root
    /// Language whose versions are listed, and where Back returns to.
    @State private var versionsLanguage: String?
    @State private var versionsReturn: Page = .root

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case .root:
                        header(title: "Playback")
                        if !player.audioTracks.isEmpty { audioSection }
                        subtitleNavSection
                        if hasActiveSubtitle { subtitleDelaySection }
                        speedSection
                        aspectSection
                    case .subtitles:
                        header(title: "Subtitles")
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
            .frame(maxWidth: panelWidth, maxHeight: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(panelInset)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.15), value: page)
        #if os(tvOS)
        .onExitCommand {
            if page == .root { onClose() } else { goBack() }
        }
        #endif
    }

    private func header(title: String) -> some View {
        HStack(spacing: 14) {
            if page != .root {
                #if os(tvOS)
                Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(TVCircleButtonStyle(diameter: 46))
                #else
                Button { goBack() } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                #endif
            }
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if page == .root {
                #if os(tvOS)
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(TVCircleButtonStyle(diameter: 46))
                #else
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                #endif
            }
        }
    }

    private var audioSection: some View {
        SettingsSection(title: "Audio") {
            ForEach(uniqueTracks(player.audioTracks)) { track in
                OptionRow(title: trackLabel(for: track),
                          selected: player.selectedAudioTrack?.id == track.id) {
                    player.selectedAudioTrack = track
                    onAudioSelected()
                }
            }
        }
    }

    private var subtitleNavSection: some View {
        SettingsSection(title: "Subtitles") {
            NavRow(title: "Language", value: currentSubtitleLabel) { page = .subtitles }
            if let active = subs.selectedTrack,
               subs.versions(for: active.languageCode, player: player).count > 1 {
                NavRow(title: "Version", value: Self.versionName(active)) {
                    showVersions(of: active.languageCode, returningTo: .root)
                }
            }
        }
    }

    private func goBack() {
        page = page == .versions ? versionsReturn : .root
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
    private func translateRow(to language: String) -> some View {
        #if canImport(Translation) && os(iOS)
        if subs.canTranslate(to: language, player: player) {
            let name = SubtitleLanguage.displayName(for: language)
            let state = subs.translationState(to: language, player: player)
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
            .disabled(running)
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
            "On this iPhone, offline after the first time. Whole sentences are translated, and the timing comes from the English version, so it stays in sync."
        case .running:
            "Keeps going if you close the player. Translated lines appear as they're ready."
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
        SettingsSection(title: "Language") {
            OptionRow(title: "Off", selected: !hasActiveSubtitle) {
                subs.apply(nil, on: player)
                page = .root
            }

            ForEach(subs.embeddedTracks(of: player)) { track in
                OptionRow(title: trackLabel(for: track),
                          selected: subs.embeddedID == track.id) {
                    subs.selectEmbedded(track, on: player)
                    page = .root
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
            ForEach(subs.byLanguage, id: \.language) { group in
                if let code = group.tracks.first?.languageCode {
                    let count = group.tracks.count
                    let active = group.tracks.contains { $0.id == subs.selectedID }
                    OptionRow(title: count > 1 ? "\(group.language) · \(count) versions" : group.language,
                              selected: active) {
                        // Show the best version at once; with a choice, open the
                        // list so another can be tried.
                        if !active, let best = subs.versions(for: code, player: player).first {
                            subs.apply(best, on: player)
                        }
                        if count > 1 {
                            showVersions(of: code, returningTo: .subtitles)
                        } else {
                            page = .root
                        }
                    }
                }
            }
            // Always reachable, including when the default language has no
            // versions at all.
            let defaultLanguage = AppSettings.shared.preferredSubtitleLanguage
            if !defaultLanguage.isEmpty { translateRow(to: defaultLanguage) }
        }
    }

    private var currentSubtitleLabel: String {
        if let id = subs.embeddedID,
           let track = subs.embeddedTracks(of: player).first(where: { $0.id == id }) {
            return trackLabel(for: track)
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
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                #if os(tvOS)
                .padding(.leading, 16)   // line the header up with the row text inset
                #endif
            content
        }
    }
}

struct OptionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        Button(action: action) { Text(title).lineLimit(1) }
            .buttonStyle(OptionRowStyle(selected: selected))
        #else
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
            .contentShape(Rectangle())
            .padding(.vertical, 4)
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
