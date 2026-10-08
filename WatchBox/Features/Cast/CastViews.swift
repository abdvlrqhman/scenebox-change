//
//  CastViews.swift
//  SceneBox
//

#if os(iOS)
import SwiftUI
import Kingfisher

// MARK: - Picking a screen

/// "Play on another screen": TVs and players found on the Wi-Fi first; adding
/// one by address and the computer link fold away until asked for.
struct CastSheet: View {
    let discovery: CastDiscovery
    let computerPageURL: URL?
    let hasSubtitles: Bool
    let onPick: (RendererDescription) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var copied = false
    @State private var showManual = false
    @State private var showComputer = false
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    devicesSection
                    VStack(spacing: 10) {
                        manualSection
                        if let computerPageURL { computerSection(computerPageURL) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Cast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onAppear { discovery.startScanning() }
        .onDisappear { discovery.stopScanning() }
    }

    // MARK: Devices

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Nearby screens")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if discovery.isScanning {
                    ProgressView().controlSize(.mini)
                    Text("Searching").font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }

            if discovery.network == nil {
                notice("wifi.slash", "Join a Wi-Fi network (or turn on Personal Hotspot for the TV) to cast.")
            } else if discovery.found.isEmpty {
                notice("tv.badge.wifi", discovery.isScanning
                       ? "Looking on your Wi-Fi…"
                       : "No screens yet. Turn the TV on and it shows up here by itself.")
            }

            ForEach(discovery.found) { item in
                Button { onPick(item.device) } label: {
                    DeviceRow(device: item.device, isReachable: item.isReachable)
                }
                .buttonStyle(.plain)
                .disabled(!item.isReachable)
                .contextMenu {
                    Button("Forget", systemImage: "trash", role: .destructive) { discovery.forget(item.device) }
                }
            }

            Text(hasSubtitles
                 ? "Smart TVs (Samsung, LG, Sony, Philips…) and Kodi. Your current subtitles go along, in sync."
                 : "Smart TVs (Samsung, LG, Sony, Philips…) and Kodi.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)
        }
        .animation(Theme.smooth, value: discovery.found)
    }

    private func notice(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 32)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rowCorner))
    }

    // MARK: Folded options

    private var manualSection: some View {
        Foldout(title: "TV not listed?", symbol: "keyboard", isOpen: $showManual) {
            HStack(spacing: 10) {
                TextField("TV's IP address, e.g. 192.168.1.20", text: $address)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($addressFocused)
                    .submitLabel(.go)
                    .onSubmit(addManually)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
                if discovery.isAddingManually {
                    ProgressView().frame(width: 56)
                } else {
                    Button("Add", action: addManually)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.onAccent)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let message = discovery.manualMessage {
                Text(message).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            Text("The address is in the TV's network settings. Windows laptop: install Kodi, then in Settings › Services › UPnP/DLNA turn on \"Enable UPnP support\" and \"Allow remote control via UPnP\".")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func computerSection(_ url: URL) -> some View {
        Foldout(title: "Watch on a computer", symbol: "laptopcomputer", isOpen: $showComputer) {
            Text(url.absoluteString)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            Text("Open it in a browser on the same Wi-Fi, or in VLC with the subtitles file. Keep SceneBox open meanwhile.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private func addManually() {
        addressFocused = false
        let text = address
        Task { await discovery.add(address: text) }
    }
}

/// A row that opens to show more.
private struct Foldout<Content: View>: View {
    let title: String
    let symbol: String
    @Binding var isOpen: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Theme.smooth) { isOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32)
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { content }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rowCorner))
    }
}

private struct DeviceRow: View {
    let device: RendererDescription
    let isReachable: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.isComputer ? "laptopcomputer" : "tv")
                .font(.title3)
                .foregroundStyle(isReachable ? Theme.onAccent : Theme.textTertiary)
                .frame(width: 44, height: 44)
                .background(isReachable ? Theme.accent : Theme.elevated,
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isReachable ? .white : Theme.textSecondary)
                    .lineLimit(1)
                Text(isReachable ? detail : "Not answering: off or on another Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isReachable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rowCorner))
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowCorner))
    }

    private var detail: String {
        let text = [device.manufacturer, device.model].filter { !$0.isEmpty }.joined(separator: " · ")
        return text.isEmpty ? "Ready" : text
    }
}

// MARK: - While casting

/// Takes over the player screen while a TV plays: the artwork "on the TV",
/// what it's doing, and the controls, which act on the TV. Side by side in
/// landscape, stacked in portrait.
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
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                backdrop
                VStack(spacing: 0) {
                    topBar
                    if landscape {
                        HStack(spacing: 32) {
                            screen.frame(maxWidth: geo.size.width * 0.42)
                            VStack(spacing: 22) {
                                info
                                controls
                            }
                            .frame(maxWidth: 460)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 16)
                        screen.frame(maxWidth: 520)
                        Spacer(minLength: 20)
                        info
                        Spacer(minLength: 20)
                        controls.frame(maxWidth: 560)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
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
                    .blur(radius: 50)
                    .opacity(0.5)
            }
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) { circleIcon("chevron.down") }
                .accessibilityLabel("Close")
            Spacer(minLength: 0)
            Button(action: onSubtitles) { circleIcon("captions.bubble") }
                .accessibilityLabel("Subtitles")
        }
        .buttonStyle(.plain)
    }

    /// The artwork framed like the screen it's playing on.
    private var screen: some View {
        ZStack {
            Theme.surface
            if let artworkURL {
                KFImage(artworkURL)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
            if cast.phase == .connecting || cast.phase == .buffering || cast.phase == .idle {
                Color.black.opacity(0.45)
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).strokeBorder(Theme.hairline))
        .overlay(alignment: .bottomLeading) { deviceBadge.padding(10) }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    private var deviceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: cast.device?.isComputer == true ? "laptopcomputer" : "tv")
                .symbolEffect(.pulse, isActive: cast.phase == .connecting || cast.phase == .buffering)
            Text(cast.device?.name ?? "TV").lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var info: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.display(26, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if subtitlesChanged || cast.isSendingSubtitles {
                Button(action: onSendSubtitles) {
                    Label(cast.isSendingSubtitles ? "Sending subtitles…" : "Send new subtitles to the TV",
                          systemImage: "captions.bubble.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.16), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(cast.isSendingSubtitles)
                .padding(.top, 4)
            }
        }
    }

    private var statusText: String {
        switch cast.phase {
        case .idle, .connecting: "Connecting to \(cast.device?.name ?? "the TV")…"
        case .buffering: "Loading on the TV…"
        case .playing: "Playing on \(cast.device?.name ?? "the TV")"
        case .paused: "Paused"
        case .finished: "Finished"
        case .failed(let message): message
        }
    }

    private var statusColor: Color {
        switch cast.phase {
        case .playing: Theme.success
        case .failed: Theme.danger
        case .paused, .finished: Theme.textTertiary
        default: Theme.warning
        }
    }

    private var controls: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Slider(value: Binding(get: { scrub ?? cast.position }, set: { scrub = $0 }),
                       in: 0...max(1, cast.duration),
                       onEditingChanged: { editing in
                           guard !editing, let target = scrub else { return }
                           cast.seek(to: target)
                           scrub = nil
                       })
                    .tint(Theme.accent)
                    .disabled(!isControllable || cast.duration <= 0)
                HStack {
                    Text(timecode(.seconds(scrub ?? cast.position)))
                    Spacer()
                    Text("-" + timecode(.seconds(max(0, cast.duration - (scrub ?? cast.position)))))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 48) {
                Button { cast.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 28))
                }
                Button { cast.togglePause() } label: {
                    Image(systemName: cast.phase == .playing || cast.phase == .buffering ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 72, height: 72)
                        .background(Theme.accent, in: Circle())
                }
                Button { cast.skip(by: 10) } label: {
                    Image(systemName: "goforward.10").font(.system(size: 28))
                }
            }
            .buttonStyle(.plain)
            .disabled(!isControllable)
            .opacity(isControllable ? 1 : 0.4)

            Button(action: onStop) {
                Label("Stop casting · watch on phone", systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
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
