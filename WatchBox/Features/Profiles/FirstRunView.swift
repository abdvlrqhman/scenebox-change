//
//  FirstRunView.swift
//  SceneBox
//

import SwiftUI

/// Decide once: how SceneBox plays things, which languages, and whether
/// downloads wait for Wi-Fi. Shown one time, after the first profile exists.
struct FirstRunView: View {
    let onDone: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(ProfileStore.self) private var profiles
    @State private var usesDebrid = false

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(welcome)
                        .font(.display(40, relativeTo: .title1))
                        .accessibilityAddTraits(.isHeader)
                    Text("Three choices, then Play just plays. You can change them later in Settings, from your avatar.")
                        .font(.synopsis)
                        .foregroundStyle(.white.opacity(0.82))
                }

                group("How should SceneBox play things?") {
                    choice("Free, from other viewers",
                           detail: "Peer-to-peer. Other viewers can see your IP address; a VPN hides it.",
                           selected: !usesDebrid) {
                        usesDebrid = false
                        settings.debridProvider = .none
                    }
                    choice("With a debrid account",
                           detail: "Faster and private: the service fetches for you. Real-Debrid, AllDebrid, Premiumize, TorBox.",
                           selected: usesDebrid) {
                        usesDebrid = true
                        if settings.debridProvider == .none { settings.debridProvider = .realDebrid }
                    }
                    if usesDebrid {
                        row("Service") {
                            Picker("Service", selection: $settings.debridProvider) {
                                ForEach(DebridProvider.allCases.filter { $0 != .none }) { provider in
                                    Text(provider.title).tag(provider)
                                }
                            }
                        }
                        SecureField("API key", text: $settings.debridAPIKey)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous))
                        if settings.debridAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Without a key, SceneBox plays peer-to-peer until you add one.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                group("Languages") {
                    row("Audio") {
                        Picker("Audio", selection: $settings.preferredAudioLanguage) {
                            ForEach(AppSettings.audioLanguageOptions, id: \.code) { option in
                                Text(option.name).tag(option.code)
                            }
                        }
                    }
                    row("Subtitles") {
                        Picker("Subtitles", selection: $settings.preferredSubtitleLanguage) {
                            ForEach(SubtitleLanguage.offered) { language in
                                Text(language.name).tag(language.code)
                            }
                        }
                    }
                }

                group("Downloads") {
                    Toggle(isOn: $settings.wifiOnly) {
                        Text("Download over Wi-Fi only").font(.body.weight(.semibold))
                    }
                    .tint(Theme.success)
                    .frame(minHeight: 48)
                    .overlay(alignment: .top) { Theme.hairline.frame(height: 0.5) }
                }

                Button(action: onDone) {
                    Text("Start watching")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 72)
            .padding(.bottom, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .foregroundStyle(.white)
        .background {
            // A projector's beam on the black: the only light before there's artwork.
            ZStack {
                Theme.background
                RadialGradient(colors: [Theme.accent.opacity(0.16), .clear],
                               center: .top, startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        }
        .onAppear { usesDebrid = settings.debridProvider != .none }
    }

    /// "Welcome, Sara", or just "Welcome" for the placeholder name a skipped profile gets.
    private var welcome: String {
        guard let name = profiles.selected?.name, name != "Me" else { return "Welcome" }
        return "Welcome, \(name)"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .sectionTitleStyle()
                .padding(.bottom, 6)
            content()
        }
    }

    /// "Audio ........ English ⌄": the label says what the picker is for.
    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        LabeledContent {
            control()
                .labelsHidden()
                .tint(.white)
        } label: {
            Text(title).font(.body.weight(.semibold))
        }
        .frame(minHeight: 48)
        .overlay(alignment: .top) { Theme.hairline.frame(height: 0.5) }
    }

    /// A hairline row you pick, with a sentence of what it means.
    private func choice(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Theme.hairline.frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
