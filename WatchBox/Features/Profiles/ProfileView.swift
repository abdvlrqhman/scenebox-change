//
//  ProfileView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadStore.self) private var downloads
    @Environment(ProfileStore.self) private var profiles
    @State private var editing: ProfileEditorView.Mode?
    @State private var confirmClearDownloads = false
    @State private var confirmClearStreamCache = false
    @State private var streamCacheBytes: Int64 = 0

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            VStack(spacing: 0) {
            #if !os(tvOS)
            RootHeader(title: "Profile") { profileMenu }
            #endif
            Form {
                PageTitleRow("Profile")
                if let profile = profiles.selected {
                    Section {
                        profileHeader(profile)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    #if os(tvOS)
                    Section {
                        Button("Switch profile") { profiles.deselect() }
                        if profiles.profiles.count < Profile.maxPerAccount {
                            Button("Add profile") { editing = .create(first: false) }
                        }
                    }
                    #endif
                }

                Section("Stream quality") {
                    Picker("Sort releases by", selection: $settings.releaseSort) {
                        ForEach(ReleaseSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    Picker("Prefer resolution", selection: $settings.preferredResolution) {
                        ForEach(["2160p", "1080p", "720p", "480p"], id: \.self) { res in
                            Text(res == "2160p" ? "4K" : res).tag(res)
                        }
                    }
                    NavigationLink {
                        QualityFilterList()
                    } label: {
                        LabeledContent("Hide qualities",
                                       value: hiddenSummary)
                    }
                }

                Section {
                    Toggle("Auto-pick best source", isOn: $settings.autoSelectSource)
                        .tint(toggleTint)
                } header: {
                    Text("Sources")
                } footer: {
                    Text("Skip the release list and start the best match automatically.")
                }

                Section {
                    ForEach(StreamProvider.queryOrder) { provider in
                        let locked = provider.requiresDebrid && !settings.hasRealDebridKey
                        Toggle(isOn: sourceBinding(provider)) {
                            if locked {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.title)
                                    Text("Needs a Real-Debrid key")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(provider.title)
                            }
                        }
                        .disabled(locked)
                        .tint(toggleTint)
                    }
                    Toggle("Extra public providers", isOn: $settings.extraSourceProviders)
                        .tint(toggleTint)
                } header: {
                    Text("Stream sources")
                } footer: {
                    if settings.enabledSources.isEmpty {
                        Text("Turn on at least one source.")
                    } else {
                        Text("Peer-to-peer streams connect you directly to other peers, who can see your IP address. Use a VPN, or a debrid service (which fetches on your behalf), if that matters to you.")
                    }
                }

                Section {
                    Toggle("Send debrid key to community sources", isOn: $settings.shareDebridKeyWithCommunitySources)
                        .tint(toggleTint)
                    LabeledContent("StremThru server") {
                        TextField("https://…", text: $settings.stremthruHost)
                            .autocorrectionDisabled()
                            .tint(.white)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }
                } header: {
                    Text("Source privacy")
                } footer: {
                    Text("Comet and StremThru are community-run servers. The Stremio protocol puts your debrid key in every request to them, so whoever runs the server can read it. Off: they're used peer-to-peer only (Comet is skipped). Torrentio's official server always receives the key.")
                }

                Section {
                    Picker("Service", selection: $settings.debridProvider) {
                        ForEach(DebridProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    if settings.debridProvider.requiresKey {
                        SecureField("API key", text: $settings.debridAPIKey)
                            .autocorrectionDisabled()
                            .tint(.white)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                } header: {
                    Text("Debrid")
                } footer: {
                    if let hint = settings.debridProvider.keyHint {
                        Text("Key: \(hint)")
                    } else {
                        Text("Stream cached torrents at full speed instead of peer-to-peer.")
                    }
                }

                Section {
                    SecureField("TMDB API key", text: $settings.tmdbAPIKey)
                        .autocorrectionDisabled()
                        .tint(.white)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Cast")
                } footer: {
                    Text("A free TMDB key adds cast photos and filmographies.")
                }

                Section {
                    Picker("Default audio", selection: $settings.preferredAudioLanguage) {
                        ForEach(AppSettings.audioLanguageOptions, id: \.code) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                    Picker("Default subtitles", selection: $settings.preferredSubtitleLanguage) {
                        ForEach(SubtitleLanguage.offered) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                    Picker("Subtitle size", selection: $settings.subtitleScale) {
                        ForEach(AppSettings.subtitleScaleOptions, id: \.self) { scale in
                            Text(String(format: "%.2g×", scale)).tag(scale)
                        }
                    }
                    SubtitleSizePreview(scale: settings.subtitleScale)
                    Toggle("Fill screen (crop)", isOn: $settings.fillScreen)
                        .tint(toggleTint)
                    Picker("Player buffer", selection: $settings.networkCacheMilliseconds) {
                        Text("2 s").tag(2000)
                        Text("3 s").tag(3000)
                        Text("5 s").tag(5000)
                        Text("10 s").tag(10000)
                        Text("20 s").tag(20000)
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("""
                    Default audio is used when a title was made in that language (or its language is unknown); a foreign title keeps its original audio instead of a dub. Subtitles in your default language are fetched from OpenSubtitles as soon as you press play.

                    Player buffer is how many seconds the player holds ahead. Larger smooths slow downloads but starts slower; 3 seconds suits most connections.
                    """)
                }

                Section {
                    LabeledContent("Downloads", value: ByteFormat.size(downloads.diskUsage))
                    Picker("Download limit", selection: $settings.storageCapBytes) {
                        Text("Unlimited").tag(Int64(0))
                        Text("5 GB").tag(Int64(5) << 30)
                        Text("10 GB").tag(Int64(10) << 30)
                        Text("25 GB").tag(Int64(25) << 30)
                        Text("50 GB").tag(Int64(50) << 30)
                    }
                    Button("Delete all downloads", role: .destructive) {
                        confirmClearDownloads = true
                    }
                    .disabled(downloads.downloads.isEmpty)

                    LabeledContent("Stream cache", value: ByteFormat.size(streamCacheBytes))
                    Picker("Stream cache limit", selection: $settings.streamCacheLimitGB) {
                        ForEach(AppSettings.streamCacheOptions, id: \.self) { gb in
                            Text(gb == 0 ? "Off" : "\(gb) GB").tag(gb)
                        }
                    }
                    Button("Clear stream cache", role: .destructive) {
                        confirmClearStreamCache = true
                    }
                    .disabled(streamCacheBytes == 0)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("New downloads won't start past the download limit. The stream cache keeps recently streamed titles on disk so re-opening them starts instantly; the oldest are evicted past its limit.")
                }

                Section {
                    Picker("Simultaneous downloads", selection: $settings.maxSimultaneousDownloads) {
                        ForEach(AppSettings.simultaneousDownloadOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    #if os(iOS)
                    Picker("Keep downloading in background", selection: $settings.backgroundDownloadMode) {
                        ForEach(BackgroundDownloadMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    if #available(iOS 26, *) {
                        Toggle("Show progress in Live Activity", isOn: $settings.downloadLiveActivity)
                            .tint(toggleTint)
                    }
                    #endif
                } header: {
                    Text("Downloads")
                } footer: {
                    #if os(iOS)
                    Text("Extra downloads wait in a queue and start automatically. iOS normally freezes an app a few seconds after you leave it, which drops every peer; background mode keeps SceneBox running while downloads are active by playing silent audio that mixes with your music. Smart uses short pulses to save battery; switch to Always-on audio if downloads still stop. Closing SceneBox from the app switcher always stops downloads. The Live Activity shows progress on the Lock Screen, but iOS may mark it failed while a torrent is still looking for peers; downloads carry on regardless.")
                    #else
                    Text("Extra downloads wait in a queue and start automatically.")
                    #endif
                }

                Section {
                    Picker("Max peers", selection: $settings.maxPeers) {
                        ForEach([20, 40, 60, 80, 100, 150, 200], id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    LabeledContent("Streaming port") {
                        TextField("Port", value: portBinding, format: .number.grouping(.never))
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            .tint(.white)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    Toggle("Download over Wi-Fi only", isOn: $settings.wifiOnly)
                        .tint(toggleTint)
                    NavigationLink("Custom trackers") {
                        TrackerEditor()
                    }
                } header: {
                    Text("Network")
                } footer: {
                    Text("Ports \(AppSettings.streamingPortRange.lowerBound)–\(AppSettings.streamingPortRange.upperBound); if it's busy the app picks a free one automatically. Wi-Fi only pauses downloads on cellular and resumes them on Wi-Fi. Custom trackers are announced in addition to each torrent's own.")
                }

                Section {
                    contactRow("Support", email: "spontaneousarray@gmail.com")
                    NavigationLink("Credits") { CreditsView() }
                } header: {
                    Text("About")
                } footer: {
                    Text("SceneBox \(appVersion) (\(buildNumber))")
                }
            }
            .hideScrollBackground()
            #if !os(tvOS)
            .contentMargins(.top, 4, for: .scrollContent)
            #endif
            }
            .background(Theme.background)
            #if os(tvOS)
            .pageTitle("Profile")
            #else
            .toolbar(.hidden, for: .navigationBar)
            .statusBarScrim()
            #endif
            .task {
                downloads.refreshDiskUsage()
                await refreshStreamCacheSize()
            }
            .tint(.white)
        }
        .confirmationDialog("Delete all downloads?",
                            isPresented: $confirmClearDownloads,
                            titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { downloads.removeAll() }
        } message: {
            Text("Every downloaded file and its resume data will be removed.")
        }
        .confirmationDialog("Clear stream cache?",
                            isPresented: $confirmClearStreamCache,
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                StreamCoordinator.purgeStreamCache()
                Task { await refreshStreamCacheSize() }
            }
        } message: {
            Text("Recently streamed titles will need to buffer again next time.")
        }
        .sheet(item: $editing) { mode in
            ProfileEditorView(mode: mode)
                .environment(profiles)
        }
    }

    private var profileMenu: some View {
        Menu {
            Button { profiles.deselect() } label: {
                Label("Switch profile", systemImage: "person.2")
            }
            if profiles.profiles.count < Profile.maxPerAccount {
                Button { editing = .create(first: false) } label: {
                    Label("Add profile", systemImage: "plus.circle")
                }
            }
        } label: {
            Image(systemName: "person.2")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
        }
        .accessibilityLabel("Profiles")
    }

    private func profileHeader(_ profile: Profile) -> some View {
        VStack(spacing: 14) {
            #if os(tvOS)
            ProfileAvatar(profile: profile, size: 180)
            #else
            ProfileAvatar(profile: profile, size: 110)
            #endif
            VStack(spacing: 6) {
                Text(profile.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Progress is saved on this device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    editing = .edit(profile)
                } label: {
                    Label("Edit Profile", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { settings.streamingPort },
            set: { settings.streamingPort = AppSettings.streamingPortRange.contains($0) ? $0 : AppSettings.defaultStreamingPort })
    }

    private func refreshStreamCacheSize() async {
        streamCacheBytes = await Task.detached(priority: .utility) { StreamCache.totalBytes() }.value
    }

    private var toggleTint: Color {
        #if os(tvOS)
        .white
        #else
        settings.accentColor
        #endif
    }

    private func sourceBinding(_ provider: StreamProvider) -> Binding<Bool> {
        Binding(
            get: { settings.enabledSources.contains(provider) },
            set: { on in
                if on { settings.enabledSources.insert(provider) }
                else { settings.enabledSources.remove(provider) }
            }
        )
    }

    private var hiddenSummary: String {
        let hidden = QualityFilter.offered.filter(settings.excludedQualities.contains)
        if hidden.isEmpty { return "None" }
        if hidden.count <= 2 { return hidden.map(\.title).joined(separator: ", ") }
        return "\(hidden.count) hidden"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    @ViewBuilder
    private func contactRow(_ title: String, email: String) -> some View {
        #if os(tvOS)
        LabeledContent(title, value: email)
        #else
        Link(destination: URL(string: "mailto:\(email)")!) {
            HStack {
                Text(title).foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(email).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        #endif
    }
}
