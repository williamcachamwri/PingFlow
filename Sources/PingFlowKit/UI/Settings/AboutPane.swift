import AppKit
import SwiftUI

/// Version and the inventory the wheel depends on. One card, hairlines instead of tinted bands, and
/// the same monospace plates the rest of the window uses — the page reads as one family rather than
/// a generic about box.
struct AboutPane: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var reduceMotion = SettingsRootView.isReduceMotion

    private var versionText: String { "\(AppInfo.version) (\(AppInfo.build))" }

    private var inventory: [AssetCatalog.Check] { AssetCatalog.shared.inventory() }
    private var missingAssets: Int { inventory.filter { !$0.present }.count }
    private var soundCount: Int { inventory.filter { $0.kind == .sound && $0.present }.count }
    private var sliceCount: Int {
        store.settings.wheelSlots.count + store.settings.emoteWheelSlots.count
    }

    var body: some View {
        SettingsPage {
            SectionCard(highlightID: "about") {
                identity
                Hairline(inset: Metrics.rowPadding)
                statsRail
            }
            .staggered(0, enabled: !reduceMotion)
        }
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(alignment: .center, spacing: 16) {
            logo
            VStack(alignment: .leading, spacing: 4) {
                Text("PingFlow")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text("A League of Legends ping wheel, native to macOS.")
                    .font(Metrics.rowSubtitle)
                    .foregroundStyle(Palette.secondaryText)
                Text(legend)
                    .font(Metrics.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            ValuePlate(missingAssets == 0 ? "Assets complete" : "\(missingAssets) missing",
                       tone: missingAssets == 0 ? .success : .warning)
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.vertical, 16)
    }

    private var legend: String {
        // operatingSystemVersionString is "Version 27.0 (Build …)"; the page wants just the number.
        let release = AppInfo.macOSVersion
            .replacingOccurrences(of: "Version ", with: "")
            .prefix { !$0.isWhitespace }
        return [versionText, AppInfo.architecture, "macOS \(release)"]
            .joined(separator: "  ·  ")
    }

    @ViewBuilder private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Palette.chipBackground)
            if let image = AssetCatalog.shared.image(named: PingDefinition.logoTexture) {
                Image(nsImage: SettingsRootView.sized(image, to: 30))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var statsRail: some View {
        HStack(spacing: 0) {
            stat("\(PingDefinition.all.count)", "Pings")
            stat("\(EmoteDefinition.all.count)", "Emotes")
            stat("\(sliceCount)", "Wheel slots")
            stat("\(soundCount)", "Sounds")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Metrics.rowPadding)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.primaryText)
            Text(label.uppercased())
                .font(Metrics.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
