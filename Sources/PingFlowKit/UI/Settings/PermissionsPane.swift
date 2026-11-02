import AppKit
import SwiftUI

struct PermissionsPane: View {
    @EnvironmentObject private var permissions: PermissionManager
    @EnvironmentObject private var engine: PingFlowEngine
    @EnvironmentObject private var store: SettingsStore

    @State private var reduceMotion = SettingsRootView.isReduceMotion

    private var granted: Bool { permissions.isGranted }

    var body: some View {
        SettingsPage {
            SectionCard(highlightID: "permissions") {
                status
                Hairline(inset: Metrics.rowPadding)
                facts
                if !granted {
                    Hairline()
                    actionRow
                }
            }
            .staggered(0, enabled: !reduceMotion)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: granted)
        .onAppear { permissions.startPolling() }
    }

    private var status: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((granted ? Palette.success : Palette.danger).opacity(0.14))
                    .frame(width: 46, height: 46)
                Image(systemName: granted ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(granted ? Palette.success : Palette.danger)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(statusText)
                    .font(Metrics.rowSubtitle)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer(minLength: 12)
            ValuePlate(granted ? "Granted" : "Not granted",
                       tone: granted ? .success : .danger, width: 84)
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var facts: some View {
        HStack(spacing: 0) {
            fact("Key it reads", store.settings.activationKey.glyph)
            fact("Displays", "\(NSScreen.screens.count)")
            fact("Tap", engine.tapStatus == .running ? "live" : "stopped")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Metrics.rowPadding)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("Open System Settings") { permissions.openAccessibilitySettings() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .controlSize(.small)
            Text("Tick PingFlow in Privacy & Security → Accessibility.")
                .font(Metrics.caption)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.rowPadding)
        .frame(minHeight: Metrics.lineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Metrics.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.tertiaryText)
            Text(value)
                .font(Metrics.mono)
                .foregroundStyle(Palette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if !store.settings.isEnabled { return "PingFlow is paused" }
        if granted {
            return engine.tapStatus == .running
                ? "Listening on \(NSScreen.screens.count) display\(NSScreen.screens.count == 1 ? "" : "s")"
                : "Granted, but the tap is not running"
        }
        return "Required to read \(store.settings.activationKey.glyph) anywhere on the system"
    }
}
