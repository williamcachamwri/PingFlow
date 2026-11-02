import AppKit
import Foundation

/// Everything the About page and a bug report need, read from the running bundle rather than
/// written twice.
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "PingFlow"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "local.PingFlow"
    }

    static var macOSVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var bundleURL: URL { Bundle.main.bundleURL }

    static var executableURL: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "PingFlow")
    }

    /// How the process was started, which decides whether the assets are inside the bundle or in
    /// the source tree next to it.
    static var assetRoot: String {
        AssetCatalog.shared.rootDirectory?.path ?? "not found"
    }

    static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "unknown"
        #endif
    }

    static var displaySummary: String {
        NSScreen.screens.enumerated().map { index, screen in
            "\(index + 1): \(Int(screen.frame.width))×\(Int(screen.frame.height)) pt"
        }.joined(separator: " · ")
    }

    /// A paste-able block for a bug report. Everything in it is local: no identifiers, no paths
    /// beyond the app's own.
    static func diagnostics(settings: AppSettings) -> String {
        let inventory = AssetCatalog.shared.inventory()
        let missing = inventory.filter { !$0.present }.map(\.name)
        let lines: [String] = [
            "\(name) \(version) (\(build)) — \(bundleIdentifier)",
            "macOS \(macOSVersion), \(architecture)",
            "Bundled: \(isBundled) | Bundle: \(bundleURL.path)",
            "Assets: \(assetRoot)",
            "Settings: \(AppPaths.supportDirectory.appendingPathComponent("settings.json").path)",
            "Displays: \(displaySummary)",
            "Accessibility: \(PermissionManager.isTrusted ? "granted" : "not granted")",
            "Assets missing: \(missing.isEmpty ? "none" : missing.joined(separator: ", "))",
            "",
            "Wheel: size \(Int(settings.wheelSize)) pt, slots \(settings.wheelSlots.map(\.rawValue).joined(separator: ","))",
            "Activation: \(settings.activationKey.rawValue), threshold \(Int(settings.dragThreshold)) pt",
            "Toggle: \(settings.toggleShortcut?.displayString ?? "none")",
            "Sounds: volume \(Int(settings.volume * 100)) %, muted \(settings.isMuted), tick \(settings.tickSoundEnabled)",
            "Appearance: \(settings.appearanceMode.rawValue), accent \(settings.accentColor.rawValue)",
            "Ping: size \(Int(settings.pingSize)) pt, \(String(format: "%.1f", settings.pingDuration)) s, intensity \(String(format: "%.2f", settings.animationIntensity)), opacity \(String(format: "%.2f", settings.overlayOpacity))",
        ]
        return lines.joined(separator: "\n")
    }
}
