//
//  CastViews.swift
//  SceneBox
//

#if os(iOS)
import SwiftUI
import Kingfisher

// MARK: - Picking a screen

/// "Play on another screen": TVs and players found on the Wi-Fi, a way to add
/// one by address, and the address to open on a computer.
struct CastSheet: View {
    let discovery: CastDiscovery
    let computerPageURL: URL?
    let hasSubtitles: Bool
    let onPick: (RendererDescription) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var copied = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                devicesSection
                manualSection
                if let computerPageURL { computerSection(computerPageURL) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Play on another screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .onAppear { discovery.startScanning() }
        .onDisappear { discovery.stopScanning() }
    }

    private var devicesSection: some View {
        Section {
            if discovery.network == nil {
                Label("Connect to Wi-Fi (or turn on Personal Hotspot for the TV) to cast.", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            }
            ForEach(discovery.found) { item in
                Button {
                    onPick(item.device)
                } label: {
                    DeviceRow(device: item.device, isReachable: item.isReachable)
                }
                .disabled(!item.isReachable)
                .swipeActions {
                    Button("Forget", role: .destructive) { discovery.forget(item.device) }
                }
            }
            if discovery.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking on your Wi-Fi…").foregroundStyle(.secondary)
                }
            } else if discovery.found.isEmpty, discovery.network != nil {
                Text("No TVs found yet. Turn the TV on; the list updates by itself.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("TVs and players")
        } footer: {
            Text(hasSubtitles
                 ? "Samsung, LG, Sony, Philips and most smart TVs, plus Kodi. The subtitles showing now go with the video, with their sync."
                 : "Samsung, LG, Sony, Philips and most smart TVs, plus Kodi.")
        }
    }

    private var manualSection: some View {
        Section {
            HStack {
                TextField("TV's IP address, e.g. 192.168.1.20", text: $address)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($addressFocused)
                    .submitLabel(.go)
                    .onSubmit(addManually)
                if discovery.isAddingManually {
                    ProgressView()
                } else {
                    Button("Add", action: addManually)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let message = discovery.manualMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("TV not listed?")
        } footer: {
            Text("The TV's address is in its network settings. Windows laptop: install Kodi, then in Settings › Services › UPnP/DLNA turn on \"Enable UPnP support\" and \"Allow remote control via UPnP\".")
        }
    }

    private func computerSection(_ url: URL) -> some View {
        Section {
            Text(url.absoluteString)
                .font(.body.monospaced())
                .textSelection(.enabled)
            HStack {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                Spacer()
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("On a computer")
        } footer: {
            Text("Open this address in a browser on a computer on the same Wi-Fi: play it right there, or open it in VLC and add the subtitles file. Keep SceneBox open meanwhile.")
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private func addManually() {
        addressFocused = false
        let text = address
        Task { await discovery.add(address: text) }
    }
}

private struct DeviceRow: View {
    let device: RendererDescription
    let isReachable: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.isComputer ? "laptopcomputer" : "tv")
                .font(.title3)
                .foregroundStyle(isReachable ? Theme.accent : .secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isReachable ? .primary : .secondary)
                Text(isReachable ? detail : "Not answering: off or on another Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var detail: String {
        [device.manufacturer, device.model].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - While casting

/// Takes over the player screen while a TV plays: where it's playing, its
/// state, and the controls, which act on the TV.
struct CastingOverlay: View {
    let cast: CastSession
    let title: String
    let artworkURL: URL?
    /// The subtitles on the phone differ from the ones the TV has.
    let subtitlesChanged: Bool
    let onSendSubtitles: () -> Void
    let onSubtitles: () -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    @State private var scrub: Double?

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                status
                Spacer(minLength: 12)
                controls
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let artworkURL {
                KFImage(artworkURL)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .opacity(0.35)
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: onClose) { circleIcon("xmark") }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onSubtitles) { circleIcon("captions.bubble") }
                .accessibilityLabel("Subtitles")
        }
        .buttonStyle(.plain)
    }

    private var status: some View {
        VStack(spacing: 10) {
            Image(systemName: cast.device?.isComputer == true ? "laptopcomputer" : "tv")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse, isActive: cast.phase == .connecting || cast.phase == .buffering)
            Text("Playing on \(cast.device?.name ?? "TV")")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if subtitlesChanged || cast.isSendingSubtitles {
                Button(action: onSendSubtitles) {
                    Label(cast.isSendingSubtitles ? "Sending subtitles…" : "Send the new subtitles to the TV",
                          systemImage: "captions.bubble.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(cast.isSendingSubtitles)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 420)
    }

    private var statusText: String {
        switch cast.phase {
        case .idle, .connecting: "Connecting…"
        case .buffering: "Loading on the TV…"
        case .playing: "Playing"
        case .paused: "Paused"
        case .finished: "Finished"
        case .failed(let message): message
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 44) {
                Button { cast.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 26))
                }
                Button { cast.togglePause() } label: {
                    Image(systemName: cast.phase == .playing || cast.phase == .buffering ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.16), in: Circle())
                }
                Button { cast.skip(by: 10) } label: {
                    Image(systemName: "goforward.10").font(.system(size: 26))
                }
            }
            .buttonStyle(.plain)
            .disabled(!isControllable)
            .opacity(isControllable ? 1 : 0.4)

            HStack(spacing: 12) {
                Text(timecode(.seconds(scrub ?? cast.position)))
                    .font(.caption.monospacedDigit())
                Slider(value: Binding(get: { scrub ?? cast.position }, set: { scrub = $0 }),
                       in: 0...max(1, cast.duration),
                       onEditingChanged: { editing in
                           guard !editing, let target = scrub else { return }
                           cast.seek(to: target)
                           scrub = nil
                       })
                    .tint(.white)
                    .disabled(!isControllable || cast.duration <= 0)
                Text(timecode(.seconds(cast.duration)))
                    .font(.caption.monospacedDigit())
            }

            Button(action: onStop) {
                Label("Stop casting and watch here", systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .foregroundStyle(Theme.onAccent)
        }
        .frame(maxWidth: 560)
    }

    private var isControllable: Bool {
        switch cast.phase {
        case .playing, .paused, .buffering, .finished: true
        default: false
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
    }
}
#endif
