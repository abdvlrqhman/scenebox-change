//
//  MediaDetailView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import Kingfisher

struct MediaDetailView: View {
    let mediaID: String
    let type: MediaType
    let fallbackTitle: String
    /// Opened from a Play on Home: start playing as soon as the page has loaded.
    var autoplay = false

    @State private var model: MediaDetailModel
    @State private var didAutoplay = false
    @State private var isSelectingEpisodes = false
    @State private var scrollToEpisodes = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotionScroll
    @State private var streamer = StreamCoordinator()
    @State private var pendingPlay: (() -> Void)?
    @State private var isAutoResolving = false
    @State private var resolveTask: Task<Void, Never>?
    @State private var batchStatus: String?
    @State private var batchMessage: String?
    @State private var toast: ToastMessage?
    @State private var resumeAt: Duration = .zero
    @Environment(DownloadStore.self) private var downloads
    @Environment(AppSettings.self) private var settings
    @Environment(WatchProgressStore.self) private var progressStore
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    init(mediaID: String, type: MediaType, fallbackTitle: String, autoplay: Bool = false) {
        self.mediaID = mediaID
        self.type = type
        self.fallbackTitle = fallbackTitle
        self.autoplay = autoplay
        _model = State(initialValue: MediaDetailModel(mediaID: mediaID, type: type))
    }

    var body: some View {
        content
            .animation(.smooth(duration: 0.35), value: model.isReady)
            .toast($toast)
            .overlay { if isAutoResolving || batchStatus != nil { resolvingOverlay } }
            .alert("Some episodes weren't added",
                   isPresented: Binding(get: { batchMessage != nil }, set: { if !$0 { batchMessage = nil } })) {
                Button("OK", role: .cancel) { batchMessage = nil }
            } message: {
                Text(batchMessage ?? "")
            }
            .background(Theme.background)
            #if os(iOS)
            .ignoresSafeArea(edges: .top)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(Platform.isMac ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) { titleActions }
            }
            .overlay(alignment: .topLeading) {
                if Platform.isMac {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding(16)
                    .accessibilityLabel("Back")
                }
            }
            #else
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationTitle(Platform.isMac ? displayTitle : "")
            .inlineNavigationBar()
            #if os(iOS)
            .onChange(of: displayTitle, initial: true) { _, title in MacWindow.setTitle(title) }
            .onDisappear { MacWindow.setTitle("") }
            #endif
            .task { model.load() }
            .onChange(of: model.isReady, initial: true) { _, ready in
                guard ready, autoplay, !didAutoplay, let detail = model.detail else { return }
                didAutoplay = true
                watch(episode: resumeEpisode(for: detail))
            }
            .onDisappear {
                cancelAutoResolve()
                if !streamer.isPresenting { streamer.stop() }
            }
            #if os(tvOS)
            .fullScreenCover(item: releaseRequestBinding, onDismiss: runPendingPlay) { request in
                ReleasePickerView(model: model, request: request) { stream in
                    handle(request: request, stream: stream)
                }
                .environment(settings)
                .environment(downloads)
                .environment(progressStore)
                .environment(watchlist)
            }
            #else
            .sheet(item: releaseRequestBinding, onDismiss: runPendingPlay) { request in
                ReleasePickerView(model: model, request: request) { stream in
                    handle(request: request, stream: stream)
                }
                .environment(settings)
                .environment(downloads)
                .environment(progressStore)
                .environment(watchlist)
                .preferredColorScheme(.dark)
            }
            #endif
            .fullScreenCover(isPresented: Binding(get: { streamer.isPresenting },
                                                  set: { if !$0 { streamer.stop() } }),
                             onDismiss: runPendingPlay) {
                StreamPlayerContainer(streamer: streamer)
                    .environment(settings)
                    .environment(downloads)
                    .environment(progressStore)
                    .environment(watchlist)
            }
    }

    private var displayTitle: String {
        if let name = model.detail?.name, !name.isEmpty { return name }
        return fallbackTitle
    }

    private var releaseRequestBinding: Binding<MediaDetailModel.ReleaseRequest?> {
        Binding(get: { model.releaseRequest },
                set: { if $0 == nil { model.dismissReleases() } })
    }

    private func runPendingPlay() {
        let action = pendingPlay
        pendingPlay = nil
        action?()
    }

    private func cancelAutoResolve() {
        resolveTask?.cancel()
        resolveTask = nil
        isAutoResolving = false
    }

    private var resolvingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(batchStatus ?? "Finding best source…")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if isAutoResolving {
                    Button("Cancel") { cancelAutoResolve() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isReady, let detail = model.detail {
            #if os(tvOS)
            TVDetailView(
                detail: detail,
                fallbackTitle: fallbackTitle,
                isBusy: streamer.isPreparing,
                cast: model.castMembers,
                selectedSeason: Binding(get: { model.selectedSeason },
                                        set: { model.selectedSeason = $0 }),
                resumeEpisode: resumeEpisode(for: detail),
                watchLabel: resumeLabel(for: detail),
                watchProgress: watchProgressFraction(for: detail),
                watchedEpisodes: progressStore.watchedEpisodes(for: mediaID),
                similar: model.similar,
                onWatch: { watch(episode: $0) },
                onDownload: { requestDownload(episode: $0) },
                onSetWatched: { setWatched($1, episode: $0, detail: detail) }
            )
            #else
            detailScroll(detail)
                .transition(.opacity)
            #endif
        } else if model.detail == nil, let message = model.errorMessage {
            EmptyStateView(systemImage: "wifi.exclamationmark",
                           title: "Couldn’t load this title", message: message,
                           actionTitle: "Try again") { model.load() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    private func detailScroll(_ detail: MediaDetail) -> some View {
        ZStack {
            if Platform.isMac {
                GeometryReader { proxy in
                    KFImage(detail.backdropURL)
                        .resizable()
                        .fade(duration: 0.3)
                        .placeholder { Theme.surface }
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay {
                            ZStack {
                                Color.black.opacity(0.45)
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: 0.35),
                                        .init(color: Theme.background.opacity(0.85), location: 0.75),
                                        .init(color: Theme.background, location: 1.0),
                                    ],
                                    startPoint: .top, endPoint: .bottom)
                            }
                        }
                }
                .ignoresSafeArea()
            }
            detailScrollContent(detail)
        }
    }

    private func detailScrollContent(_ detail: MediaDetail) -> some View {
        ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                BannerHeader(detail: detail, fallbackTitle: fallbackTitle)

                actions(for: detail)
                if let synopsis = detail.description, !synopsis.isEmpty {
                    ExpandableText(text: synopsis, lineLimit: 3, font: .synopsis, color: .white.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.gutter)
                }
                if detail.type == .series, !detail.seasons.isEmpty {
                    EpisodeSection(
                        detail: detail,
                        selectedSeason: Binding(
                            get: { model.selectedSeason },
                            set: { model.selectedSeason = $0 }),
                        isSelecting: $isSelectingEpisodes,
                        watchedEpisodes: progressStore.watchedEpisodes(for: mediaID),
                        episodeFraction: { progressStore.episodeFraction(mediaID: mediaID, episodeID: $0.id) },
                        onWatch: { watch(episode: $0) },
                        onDownload: { requestDownload(episode: $0) },
                        onDownloadEpisodes: { downloadEpisodes($0) },
                        onSetWatched: { setWatched($1, episode: $0, detail: detail) },
                        runtimeMinutes: detail.runtime.flatMap { Int($0.prefix { $0.isNumber }) },
                        resumeTimeLeft: timeLeftText(for: detail)
                    )
                    .id("episodes")
                }
                if !model.castMembers.isEmpty || !detail.cast.isEmpty || !detail.directors.isEmpty {
                    CastRow(members: model.castMembers, names: detail.cast,
                            crew: detail.directors.map { ($0, "Director") } + detail.writers.map { ($0, "Writer") })
                }
                crew(for: detail)
                moreLikeThis
            }
            .padding(.bottom, 40)
        }
        .onChange(of: scrollToEpisodes) { _, go in
            guard go else { return }
            scrollToEpisodes = false
            proxy.scrollTo("episodes", anchor: .top)
        }
        .task {
            // `-SBDetailScroll episodes` opens the page at that section (screenshots, debugging).
            guard let section = UserDefaults.standard.string(forKey: "SBDetailScroll") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            proxy.scrollTo(section, anchor: .top)
        }
        }
    }

    private func actions(for detail: MediaDetail) -> some View {
        let busy = streamer.isPreparing || isAutoResolving || batchStatus != nil
        let timeLeft = timeLeftText(for: detail)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    watch(episode: resumeEpisode(for: detail))
                } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            ViewThatFits(in: .horizontal) {
                                Text(resumeLabel(for: detail) ?? "Play")
                                    .lineLimit(1)
                                Text(resumeLabel(for: detail, compact: true) ?? "Play")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                        .font(.headline)
                        if let timeLeft {
                            Text(timeLeft)
                                .font(.caption.weight(.semibold))
                                .opacity(0.72)
                        }
                    }
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: timeLeft == nil ? 52 : 60)
                    .background(Theme.accent, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .layoutPriority(1)          // the main action keeps its label; the rest are icons
                .accessibilityHint(timeLeft ?? "")

                if detail.type == .series {
                    Menu {
                        if let episode = resumeEpisode(for: detail) ?? firstEpisode(of: detail) {
                            Button {
                                requestDownload(episode: episode)
                            } label: {
                                Label("Download \(episode.label)", systemImage: "arrow.down.circle")
                            }
                        }
                        let season = detail.episodes(inSeason: model.selectedSeason)
                        Button {
                            downloadEpisodes(season)
                        } label: {
                            Label(model.selectedSeason == 0 ? "Download All Specials" : "Download Season \(model.selectedSeason)",
                                  systemImage: "square.and.arrow.down.on.square")
                        }
                        .disabled(downloadableEpisodes(season).isEmpty)
                        Button {
                            isSelectingEpisodes = true
                            withAnimation(reduceMotionScroll ? nil : Theme.smooth) { scrollToEpisodes = true }
                        } label: {
                            Label("Select Episodes…", systemImage: "checklist")
                        }
                    } label: {
                        actionIcon("arrow.down.circle", tint: .white)
                    }
                    .accessibilityLabel("Download")
                } else {
                    let downloaded = downloads.isDownloaded(mediaID: mediaID)
                    Button {
                        requestDownload(episode: firstEpisode(of: detail))
                    } label: {
                        actionIcon(downloaded ? "arrow.down.circle.fill" : "arrow.down.circle", tint: .white)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(downloaded ? "Downloaded" : "Download")
                }

                Button {
                    watchlist.toggle(id: mediaID, mediaType: type,
                                     title: detail.name.isEmpty ? fallbackTitle : detail.name,
                                     posterURL: detail.posterURL)
                } label: {
                    actionIcon(isInWatchlist ? "checkmark" : "plus", tint: .white)
                }
                .buttonStyle(.pressable)
                .sensoryFeedback(.selection, trigger: isInWatchlist)
                .accessibilityLabel(isInWatchlist ? "Remove from Watchlist" : "Add to Watchlist")
            }

            // What the round buttons mean right now, in words.
            let status = statusLine(for: detail)
            if !status.isEmpty {
                Text(status)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: Platform.isMac ? 480 : .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
    }

    /// "Downloaded   In your Watchlist   Watched", for movies (episodes show their own).
    private func statusLine(for detail: MediaDetail) -> String {
        guard detail.type == .movie else { return isInWatchlist ? "In your Watchlist" : "" }
        var parts: [String] = []
        if downloads.isDownloaded(mediaID: mediaID) { parts.append("Downloaded") }
        if isInWatchlist { parts.append("In your Watchlist") }
        if progressStore.isMovieWatched(mediaID) { parts.append("Watched") }
        return parts.joined(separator: "   ")
    }

    /// "33m left" or "1h 20m left" for what Resume would play.
    private func timeLeftText(for detail: MediaDetail) -> String? {
        guard watchProgressFraction(for: detail) != nil, let saved = savedProgress, saved.durationSeconds > 0 else { return nil }
        let minutes = Int(((saved.durationSeconds - saved.positionSeconds) / 60).rounded())
        guard minutes > 0 else { return nil }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes) min left"
    }

    private func toggleMovieWatched(_ detail: MediaDetail) {
        let watched = progressStore.isMovieWatched(mediaID)
        progressStore.setMovieWatched(!watched, id: mediaID,
                                      title: detail.name.isEmpty ? fallbackTitle : detail.name,
                                      posterURL: detail.posterURL)
        toast = ToastMessage(text: watched ? "Marked as unwatched" : "Marked as watched",
                             systemImage: watched ? "eye.slash" : "checkmark.circle.fill")
    }

    #if os(iOS)
    /// Share and the overflow menu: second-tier actions, out of Play's way.
    @ViewBuilder private var titleActions: some View {
        if let detail = model.detail {
            if mediaID.hasPrefix("tt"), let url = URL(string: "https://www.imdb.com/title/\(mediaID)/") {
                ShareLink(item: url, subject: Text(displayTitle)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            Menu {
                Button {
                    model.requestReleases(intent: .watch, episode: resumeEpisode(for: detail))
                } label: {
                    Label("Choose Another Version", systemImage: "list.bullet")
                }
                if let trailer = detail.trailerURL {
                    Button { openURL(trailer) } label: {
                        Label("Watch Trailer", systemImage: "play.rectangle")
                    }
                }
                if detail.type == .movie {
                    let watched = progressStore.isMovieWatched(mediaID)
                    Button { toggleMovieWatched(detail) } label: {
                        Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                              systemImage: watched ? "eye.slash" : "checkmark.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }
    #endif

    /// The round companions to the play button: same height, quiet surface.
    private func actionIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 52, height: 52)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
            .contentShape(Circle())
    }

    private var isInWatchlist: Bool { watchlist.contains(mediaID) }

    private func firstEpisode(of detail: MediaDetail) -> Episode? {
        guard detail.type == .series else { return nil }
        return detail.episodes(inSeason: model.selectedSeason).first
    }

    // MARK: - Watch / Download

    private func watch(episode: Episode?) {
        resumeAt = startPosition(for: episode)
        if let download = downloads.completedDownload(mediaID: mediaID, episodeLabel: episode?.label) {
            playOffline(download, episode: episode)
        } else {
            watchByStreaming(episode: episode)
        }
    }

    private func watchByStreaming(episode: Episode?) {
        guard settings.autoSelectSource else {
            model.requestReleases(intent: .watch, episode: episode)
            return
        }
        resolveTask = Task {
            isAutoResolving = true
            let ranked = await model.rankedStreams(for: episode)
            guard !Task.isCancelled else { return }
            isAutoResolving = false
            if let stream = ranked.first {
                startWatch(stream: stream, episode: episode,
                           fallbacks: Array(ranked.dropFirst().filter { !$0.isDebrid }))
            } else { model.requestReleases(intent: .watch, episode: episode) }
        }
    }

    private func playOffline(_ download: Download, episode: Episode?) {
        Task {
            guard let url = await downloads.localFileURL(for: download) else {
                watchByStreaming(episode: episode)
                return
            }
            let detail = model.detail
            let name = detail?.name ?? fallbackTitle
            let label = [name, episode?.label].compactMap { $0 }.joined(separator: " · ")
            let startAt = resumeAt
            resumeAt = .zero
            let subtitleContext = SubtitleContext(
                imdbID: mediaID, type: type,
                season: episode?.season, episode: episode?.episode)
                .withRelease(download.record.localRelativePath ?? download.record.releaseName)
                .withSource(SourceKey.make(streamID: download.record.torrentKey,
                                           fileIndex: download.record.fileIndex))
            let progressContext = WatchProgressContext(
                mediaID: mediaID, mediaType: type, title: name, posterURL: detail?.posterURL,
                season: episode?.season, episode: episode?.episode, episodeID: episode?.id)
            streamer.playLocalFile(at: url, title: label, subtitleContext: subtitleContext,
                                   episodes: makeEpisodePlaylist(current: episode, detail: detail),
                                   startAt: startAt, progress: progressContext,
                                   originalAudioLanguage: model.originalLanguage)
        }
    }

    private func isWatchTargetDownloaded(for detail: MediaDetail) -> Bool {
        downloads.isDownloaded(mediaID: mediaID,
                               episodeLabel: resumeEpisode(for: detail)?.label)
    }

    private func requestDownload(episode: Episode?) {
        guard settings.autoSelectSource else {
            model.requestReleases(intent: .download, episode: episode)
            return
        }
        resolveTask = Task {
            isAutoResolving = true
            let stream = await model.bestStream(for: episode)
            guard !Task.isCancelled else { return }
            isAutoResolving = false
            if let stream { download(stream: stream, episode: episode) }
            else { model.requestReleases(intent: .download, episode: episode) }
        }
    }

    /// Finds the best source for each episode (using the quality settings, a
    /// few lookups at a time) and queues them in episode order. Episodes that
    /// already have a download, or haven't aired yet, are skipped.
    private func downloadEpisodes(_ episodes: [Episode]) {
        let wanted = downloadableEpisodes(episodes)
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        guard !wanted.isEmpty, batchStatus == nil else { return }

        // Paused or failed ones just resume with the source they already have.
        var toResolve: [Episode] = []
        for episode in wanted {
            if let existing = downloads.download(mediaID: mediaID, episodeLabel: episode.label) {
                downloads.resume(existing)
            } else {
                toResolve.append(episode)
            }
        }
        guard !toResolve.isEmpty else { return }

        batchStatus = "Finding sources… 0 of \(toResolve.count)"
        Task {
            var found: [Int: TorrentStream] = [:]
            var finished = 0
            await withTaskGroup(of: (Int, TorrentStream?).self) { group in
                var next = 0
                func enqueue() {
                    guard next < toResolve.count else { return }
                    let index = next, episode = toResolve[index]
                    next += 1
                    group.addTask { (index, await model.bestStream(for: episode)) }
                }
                for _ in 0..<min(3, toResolve.count) { enqueue() }
                for await (index, stream) in group {
                    if let stream { found[index] = stream }
                    finished += 1
                    batchStatus = "Finding sources… \(finished) of \(toResolve.count)"
                    enqueue()
                }
            }
            var missing: [String] = []
            for (index, episode) in toResolve.enumerated() {
                if let stream = found[index] {
                    download(stream: stream, episode: episode, announce: false)
                } else {
                    missing.append(episode.label)
                }
            }
            batchStatus = nil
            let added = toResolve.count - missing.count
            if added > 0 {
                toast = ToastMessage(text: added == 1 ? "Added 1 episode to Downloads"
                                                      : "Added \(added) episodes to Downloads",
                                     systemImage: "arrow.down.circle.fill")
            }
            if !missing.isEmpty {
                batchMessage = "No sources found for \(missing.joined(separator: ", ")). Try them one by one or check your source settings."
            }
        }
    }

    /// Aired episodes with no download yet, or one that's paused or failed.
    private func downloadableEpisodes(_ episodes: [Episode]) -> [Episode] {
        let now = Date()
        return episodes.filter { episode in
            if let released = episode.released, released > now { return false }
            guard let existing = downloads.download(mediaID: mediaID, episodeLabel: episode.label) else { return true }
            return existing.phase == .failed || existing.phase == .paused
        }
    }

    private func handle(request: MediaDetailModel.ReleaseRequest, stream: TorrentStream) {
        let fallbacks = model.fallbacks(after: stream)
        model.dismissReleases()
        switch request.intent {
        case .watch:
            pendingPlay = { startWatch(stream: stream, episode: request.episode, fallbacks: fallbacks) }
        case .download:
            download(stream: stream, episode: request.episode)
        }
    }

    private func startWatch(stream: TorrentStream, episode: Episode?,
                            fallbacks: [TorrentStream] = []) {
        let detail = model.detail
        let name = detail?.name ?? fallbackTitle
        let label = [name, episode?.label].compactMap { $0 }.joined(separator: " · ")
        let backdrop = detail?.backdropURL ?? detail?.posterURL
        let logo = detail?.logoURL
        let subtitleContext = SubtitleContext(
            imdbID: mediaID, type: type,
            season: episode?.season, episode: episode?.episode)
            .withRelease(stream.title)
            .withSource(SourceKey.make(stream))

        let playlist = makeEpisodePlaylist(current: episode, detail: detail)
        // A version that won't start hands back to the version list, from the player's error card.
        streamer.onChooseVersion = {
            pendingPlay = { model.requestReleases(intent: .watch, episode: episode) }
            streamer.stop()
        }

        let startAt = resumeAt
        resumeAt = .zero
        let progressContext = WatchProgressContext(
            mediaID: mediaID, mediaType: type, title: name,
            posterURL: detail?.posterURL,
            season: episode?.season, episode: episode?.episode, episodeID: episode?.id)

        if stream.isDebrid, let url = stream.url {
            SourceMemory.remember(stream, mediaID: mediaID, season: episode?.season, episode: episode?.episode)
            streamer.playDebrid(url: url, title: label, backdropURL: backdrop, logoURL: logo,
                                subtitleContext: subtitleContext, episodes: playlist,
                                startAt: startAt, progress: progressContext,
                                originalAudioLanguage: model.originalLanguage)
        } else {
            streamer.play(stream, title: label, backdropURL: backdrop, logoURL: logo,
                          subtitleContext: subtitleContext, episodes: playlist,
                          startAt: startAt, resumeFraction: resumeFraction(for: episode),
                          progress: progressContext,
                          originalAudioLanguage: model.originalLanguage,
                          fallbacks: fallbacks)
        }
    }

    // MARK: - Resume ("Continue Watching")

    private var savedProgress: WatchProgress? { progressStore.progress(for: mediaID) }

    private func resumeEpisode(for detail: MediaDetail) -> Episode? {
        detail.resumeEpisode(saved: savedProgress, watched: progressStore.watchedEpisodes(for: mediaID),
                             fallback: firstEpisode(of: detail))
    }

    private func setWatched(_ watched: Bool, episode: Episode, detail: MediaDetail) {
        progressStore.setWatched(watched, episode: episode, mediaID: mediaID, mediaType: type,
                                 title: detail.name.isEmpty ? fallbackTitle : detail.name,
                                 posterURL: detail.posterURL)
    }

    private func resumeLabel(for detail: MediaDetail, compact: Bool = false) -> String? {
        if detail.type == .movie {
            guard let saved = savedProgress, !saved.isFinished else { return nil }
            return "Resume"
        }
        guard let ep = resumeEpisode(for: detail) else { return nil }
        let code = "S\(ep.season) E\(ep.episode)"
        if compact { return code }
        let resuming = savedProgress.map { !$0.isFinished && $0.episodeID == ep.id } ?? false
        return resuming ? "Resume \(code)" : "Watch \(code)"
    }

    private func watchProgressFraction(for detail: MediaDetail) -> Double? {
        guard let saved = savedProgress, !saved.isFinished, saved.fraction > 0 else { return nil }
        if detail.type == .movie { return min(saved.fraction, 1) }
        guard let ep = resumeEpisode(for: detail), saved.episodeID == ep.id else { return nil }
        return min(saved.fraction, 1)
    }

    private func startPosition(for episode: Episode?) -> Duration {
        guard let saved = savedProgress, !saved.isFinished else { return .zero }
        if type == .movie { return .seconds(saved.positionSeconds) }
        guard let episode, saved.episodeID == episode.id else { return .zero }
        return .seconds(saved.positionSeconds)
    }

    private func resumeFraction(for episode: Episode?) -> Double? {
        guard let saved = savedProgress, !saved.isFinished, saved.fraction > 0 else { return nil }
        if type == .movie { return saved.fraction }
        guard let episode, saved.episodeID == episode.id else { return nil }
        return saved.fraction
    }

    private func download(stream: TorrentStream, episode: Episode?, announce: Bool = true) {
        let detail = model.detail
        if announce {
            toast = ToastMessage(text: episode.map { "Downloading \($0.label)" } ?? "Download started",
                                 systemImage: "arrow.down.circle.fill")
        }
        downloads.add(
            stream: stream,
            title: detail?.name ?? fallbackTitle,
            mediaID: mediaID,
            mediaType: type,
            posterURL: detail?.posterURL,
            episode: episode)
    }

    private func makeEpisodePlaylist(current: Episode?, detail: MediaDetail?) -> EpisodePlaylist? {
        guard let current, let detail, !detail.episodes.isEmpty else { return nil }
        return EpisodePlaylist(current: current, all: detail.episodes, mediaID: mediaID) { episode in
            playEpisode(episode)
        }
    }

    private func playEpisode(_ episode: Episode) {
        resumeAt = startPosition(for: episode)
        if let download = downloads.completedDownload(mediaID: mediaID, episodeLabel: episode.label) {
            playOffline(download, episode: episode)
            return
        }
        Task {
            let ranked = await model.rankedStreams(for: episode)
            guard streamer.isPresenting else { return }     // the viewer closed the player meanwhile
            if let stream = ranked.first {
                startWatch(stream: stream, episode: episode,
                           fallbacks: Array(ranked.dropFirst().filter { !$0.isDebrid }))
            } else {
                // Close the player first; the source list opens once it's gone.
                pendingPlay = { model.requestReleases(intent: .watch, episode: episode) }
                streamer.stop()
            }
        }
    }

    @ViewBuilder
    private var moreLikeThis: some View {
        #if os(iOS)
        if !model.similar.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("More Like This")
                    .sectionTitleStyle()
                    .padding(.horizontal, Theme.gutter)
                HorizontalShelfScroller {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(model.similar) { item in
                            PosterLink(item: item) {
                                PosterCard(item: item).frame(width: PosterMetrics.shelfWidth(sizeClass))
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
        #endif
    }

    private func crew(for detail: MediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let country = detail.country, !country.isEmpty {
                CreditLine(label: "Country", value: country)
            }
            if let awards = detail.awards, !awards.isEmpty {
                CreditLine(label: "Awards", value: awards)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct BannerHeader: View {
    let detail: MediaDetail?
    let fallbackTitle: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room for the status bar and the glass top bar over the frame.
    private let chromeAllowance: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !Platform.isMac {
                let reduceMotion = self.reduceMotion
                // The image sits in an overlay so its fill size can never widen
                // the page; the clear frame alone decides the layout.
                Color.clear
                    .aspectRatio(Theme.scopeAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        KFImage(detail?.backdropURL)
                            .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 1400, height: 900)))
                            .cacheOriginalImage()
                            .resizable()
                            .fade(duration: 0.25)
                            .placeholder { Theme.surface }
                            .scaledToFill()
                    }
                    .clipped()
                    // The frame dissolves into its own light instead of ending on a hard edge.
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    // Pull down to stretch, in answer to the finger only.
                    .visualEffect { content, proxy in
                        let minY = reduceMotion ? 0 : proxy.frame(in: .scrollView).minY
                        return content.scaleEffect(minY > 0 ? 1 + minY / 300 : 1, anchor: .bottom)
                    }
                    .padding(.top, chromeAllowance)
            }

            titleTreatment
                .padding(.horizontal, Theme.gutter)
        }
        .padding(.top, Platform.isMac ? 120 : 0)
        .background(alignment: .top) {
            AmbientBackdrop(url: detail?.backdropURL ?? detail?.posterURL, height: 620)
        }
    }

    private var titleTreatment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail?.name ?? fallbackTitle)
                .font(.display(40, relativeTo: .title1))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(facts(detail).joined(separator: "   "))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let rating = detail.imdbRating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .accessibilityLabel(String(format: "Rated %.1f", rating))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2008–2013   5 seasons   Crime, Drama   #3 in Shows": spaced, not dotted.
    private func facts(_ detail: MediaDetail) -> [String] {
        let seasons = detail.seasons.filter { $0 > 0 }.count
        let length = detail.type == .series ? (seasons > 0 ? "\(seasons) season\(seasons == 1 ? "" : "s")" : nil) : detail.runtime
        let genres = detail.genres.prefix(2).joined(separator: ", ")
        return [detail.year, length, genres.isEmpty ? nil : genres, HomeModel.topTenPlaces[detail.id]].compactMap { $0 }
    }

}

private struct CastRow: View {
    let members: [CastMember]
    let names: [String]
    /// Directors and writers, under the cast in the same list.
    var crew: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cast & crew")
                .sectionTitleStyle()
                .padding(.bottom, 6)
            if members.isEmpty {
                ForEach(names.prefix(8), id: \.self) { name in
                    personRow(name: name, role: nil, photo: nil)
                }
            } else {
                ForEach(members.prefix(10)) { member in
                    NavigationLink(value: member) {
                        personRow(name: member.name, role: member.role, photo: member.photoURL)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(crew.indices, id: \.self) { index in
                personRow(name: crew[index].0, role: crew[index].1, photo: nil)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    /// "Bryan Cranston ... Walter White", over a hairline.
    private func personRow(name: String, role: String?, photo: URL?) -> some View {
        HStack(spacing: 12) {
            if let photo {
                KFImage(photo)
                    .resizable()
                    .placeholder { Theme.surface }
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            }
            Text(name)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let role, !role.isEmpty {
                Text(role)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

private struct CreditLine: View {
    let label: String
    let value: String
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth: CGFloat = 78

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
