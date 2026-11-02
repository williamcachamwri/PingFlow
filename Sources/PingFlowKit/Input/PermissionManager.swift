import AppKit
import ApplicationServices
import Combine

/// Accessibility is the one permission the app cannot work without: an event tap needs it.
/// The page this feeds never leaves the user guessing — status, why, how, a button to the right
/// pane, and a retry that does not restart the tap in a loop.
@MainActor
final class PermissionManager: ObservableObject {
    /// Safe to call from any thread, including the tap's.
    nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    @Published private(set) var isGranted: Bool
    /// True when macOS says we are trusted but the tap still could not be created — the stale
    /// entry an ad-hoc signed build leaves behind after an update.
    @Published var needsManualRepair = false
    @Published private(set) var lastCheckedAt = Date()

    private var pollTask: Task<Void, Never>?

    init() {
        isGranted = PermissionManager.isTrusted
    }

    /// Adds the app to the Accessibility list and shows the system prompt. `true` when already granted.
    @discardableResult
    func requestAccess(showingPrompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: showingPrompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isGranted = trusted
        lastCheckedAt = Date()
        return trusted
    }

    func refresh() {
        let now = PermissionManager.isTrusted
        lastCheckedAt = Date()
        if now != isGranted {
            Log.input.info("Accessibility status changed to \(now ? "granted" : "revoked", privacy: .public)")
        }
        isGranted = now
    }

    /// Polls while the Permissions page is on screen, because macOS gives no notification here.
    /// 1.5 s matches the reference; anything faster is wasted work, anything slower feels broken.
    func startPolling(interval: Duration = .milliseconds(1500)) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Opens the exact pane, so nobody has to hunt for the checkbox.
    func openAccessibilitySettings() {
        requestAccess(showingPrompt: true)
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        Log.input.warning("Could not open the Accessibility pane")
    }

    /// Login Items, for the Launch at Login row when `SMAppService` needs the user's hand.
    func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.general",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        Log.input.warning("Could not open the Login Items pane")
    }
}
