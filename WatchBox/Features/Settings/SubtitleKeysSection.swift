//
//  SubtitleKeysSection.swift
//  SceneBox
//

import SwiftUI

/// Keys for extra subtitle catalogues. Typed into drafts, stored (in the
/// Keychain) only on Save, and each saved key is tried once so a typo shows up
/// here instead of as "no subtitles" in the player.
struct SubtitleKeysSection: View {
    @Environment(AppSettings.self) private var settings

    @State private var wyzie = ""
    @State private var subdl = ""
    @State private var subsource = ""
    @State private var results: [SubtitleKeyCheck.Provider: SubtitleKeyCheck.Result] = [:]
    @State private var checking = false
    @State private var loaded = false

    private var hasChanges: Bool {
        clean(wyzie) != settings.wyzieAPIKey
            || clean(subdl) != settings.subdlAPIKey
            || clean(subsource) != settings.subsourceAPIKey
    }

    var body: some View {
        Section {
            field(.wyzie, text: $wyzie)
            field(.subdl, text: $subdl)
            field(.subsource, text: $subsource)
            Button(action: save) {
                HStack {
                    Spacer()
                    if checking {
                        ProgressView().controlSize(.small)
                        Text("Checking keys…")
                    } else {
                        Text(hasChanges ? "Save" : "Saved")
                    }
                    Spacer()
                }
                .font(.body.weight(.semibold))
            }
            .disabled(!hasChanges || checking)
        } header: {
            Text("Subtitle sources")
        } footer: {
            Text("OpenSubtitles is always searched. Each key adds another catalogue, all searched together, so there are more versions to pick from. Keys stay on this device. Free keys: wyzie.io, subdl.com (Profile › API key), subsource.net (My Profile).")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            wyzie = settings.wyzieAPIKey
            subdl = settings.subdlAPIKey
            subsource = settings.subsourceAPIKey
        }
    }

    private func field(_ provider: SubtitleKeyCheck.Provider, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField("\(provider.title) key", text: text)
                .autocorrectionDisabled()
                .tint(.white)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: text.wrappedValue) { _, _ in results[provider] = nil }
            if let result = results[provider] {
                Label(result.message, systemImage: result.symbol)
                    .font(.caption)
                    .foregroundStyle(result.color)
            }
        }
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let keys: [(SubtitleKeyCheck.Provider, String)] = [
            (.wyzie, clean(wyzie)), (.subdl, clean(subdl)), (.subsource, clean(subsource)),
        ]
        settings.wyzieAPIKey = keys[0].1
        settings.subdlAPIKey = keys[1].1
        settings.subsourceAPIKey = keys[2].1
        wyzie = keys[0].1
        subdl = keys[1].1
        subsource = keys[2].1
        results = [:]

        let toCheck = keys.filter { !$0.1.isEmpty }
        guard !toCheck.isEmpty else { return }
        checking = true
        Task {
            await withTaskGroup(of: (SubtitleKeyCheck.Provider, SubtitleKeyCheck.Result).self) { group in
                for (provider, key) in toCheck {
                    group.addTask { (provider, await SubtitleKeyCheck.check(provider, key: key)) }
                }
                for await (provider, result) in group { results[provider] = result }
            }
            checking = false
        }
    }
}

private extension SubtitleKeyCheck.Result {
    var message: String {
        switch self {
        case .works: "Saved, and it works"
        case .rejected: "Saved, but the service rejected this key"
        case .unreachable: "Saved. Couldn't reach the service to check it"
        }
    }

    var symbol: String {
        switch self {
        case .works: "checkmark.circle.fill"
        case .rejected: "xmark.octagon.fill"
        case .unreachable: "wifi.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .works: Theme.success
        case .rejected: Theme.danger
        case .unreachable: Theme.warning
        }
    }
}
