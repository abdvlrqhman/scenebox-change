//
//  RootHeader.swift
//  SceneBox
//

import SwiftUI

/// Title row for the four tab screens. Replaces the large navigation title,
/// which left an empty toolbar row and a tall title block at the top of every
/// page; this sits right under the status bar with the screen's actions beside it.
struct RootHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.display(34))
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

extension RootHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Round icon button used in headers.
struct HeaderIconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Fades content out under the status bar on screens without a navigation
    /// bar, so scrolled rows never sit behind the clock.
    func statusBarScrim() -> some View {
        overlay(alignment: .top) {
            GeometryReader { geo in
                LinearGradient(colors: [Theme.background, Theme.background.opacity(0.8), Theme.background.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.safeAreaInsets.top + 10)
                    .offset(y: -geo.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Which tab is showing; lets one screen send the viewer to another.
@MainActor
@Observable
final class TabRouter {
    static let shared = TabRouter()

    var tab: AppTab = AppTab.initial
    /// Set when another screen asks for search; the Search tab focuses its field.
    var focusSearch = false

    private init() {}

    func openSearch() {
        tab = .search
        focusSearch = true
    }
}
