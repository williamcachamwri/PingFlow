import AppKit
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var engine: PingFlowEngine
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var loginItems: LoginItemController

    @State private var confirmReset = false
    @State private var loginMessage: String?
    @State private var reduceMotion = SettingsRootView.isReduceMotion

    var body: some View {
        SettingsPage {
            SectionCard(highlightID: "isEnabled") {
                if let recovery {
                    LineRow(recovery.title, subtitle: recovery.detail,
                            icon: AnyView(IconChip(symbol: "exclamationmark.shield", tint: Palette.warning))) {
                        Button(recovery.action) { recovery.run() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Hairline(inset: Metrics.rowPadding)
                }

                LineRow("Enable", highlightID: "isEnabled") {
                    PingSwitch(isOn: store.binding(\.isEnabled))
                }
                LineRow("Launch at login", divider: true, highlightID: "launchAtLogin") {
                    PingSwitch(isOn: loginBinding)
                }
                LineRow("Menu bar icon", divider: true, highlightID: "showMenuBarIcon") {
                    PingSwitch(isOn: store.binding(\.showMenuBarIcon))
                }
                LineRow("Dock icon", divider: true, highlightID: "showDockIconWhileSettingsOpen") {
                    PingSwitch(isOn: store.binding(\.showDockIconWhileSettingsOpen))
                }
            }
            .staggered(0, enabled: !reduceMotion)

            if let loginMessage {
                NoteCard(loginMessage, tone: .danger).staggered(1, enabled: !reduceMotion)
            }

            SectionCard(highlightID: "reset") {
                LineRow("Reset all settings",
                        subtitle: "Back to the League arrangement and every default.",
                        icon: AnyView(IconChip(symbol: "arrow.counterclockwise", tint: Palette.danger)),
                        highlightID: "reset",
                        action: { confirmReset = true }) {
                    ValuePlate("Reset", tone: .danger)
                }
            }
            .staggered(2, enabled: !reduceMotion)
        }
        .confirmationDialog("Reset all settings?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) { }
        }
    }

    /// The only row this page adds by itself: when the wheel genuinely cannot hear the key, say so
    /// and hand over the one button that fixes it.
    private var recovery: (title: String, detail: String, action: String, run: () -> Void)? {
        if !permissions.isGranted {
            return ("Accessibility is off", "The wheel cannot read \(store.settings.activationKey.glyph).",
                    "Open System Settings", { permissions.openAccessibilitySettings() })
        }
        if store.settings.isEnabled, engine.tapStatus != .running {
            return ("The tap stopped", "PingFlow is running but not listening.",
                    "Retry", { engine.retryTap() })
        }
        return nil
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { if case .enabled = loginItems.state { return true }; return false },
            set: { wantsOn in
                if let reason = loginItems.setEnabled(wantsOn) {
                    loginMessage = reason
                } else {
                    loginMessage = nil
                }
                if wantsOn, loginItems.state == .disabled {
                    loginMessage = "Turn on in System Settings → General → Login Items."
                    loginItems.openLoginItemsSettings()
                }
            }
        )
    }
}
