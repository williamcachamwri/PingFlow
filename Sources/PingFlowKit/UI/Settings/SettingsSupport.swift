import AppKit
import SwiftUI

extension SettingsStore {
    /// A two-way binding into the settings, so a pane never has to hand-write get/set pairs.
    /// Writing goes through `update`, which normalises and schedules the save.
    @MainActor
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { newValue in self.update { $0[keyPath: keyPath] = newValue } })
    }

    /// The same, for a value the store would otherwise repair on the way in — a switch whose
    /// off position must be written exactly as the user left it.
    @MainActor
    func commitBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { newValue in self.commit { $0[keyPath: keyPath] = newValue } })
    }
}

/// The page-level layout: a flat column of cards, each arriving a beat after the last, exactly the
/// way the reference lists its categories.
struct SettingsPage<Content: View>: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var router: SettingsRouter
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionGap) { content }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: store.settings.isEnabled)
        .onChange(of: router.highlight) { next in
            guard let next else { return }
            // A jump from search should not leave the ring on forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if router.highlight == next { router.highlight = nil }
            }
        }
    }
}
