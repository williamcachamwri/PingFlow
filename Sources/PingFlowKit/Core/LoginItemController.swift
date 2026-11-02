import Foundation
import AppKit
import ServiceManagement

/// Launch at Login, through the supported API. `SMAppService.mainApp` is the only route that
/// works for an unsigned bundle without a helper target, and it reports back honestly when the
/// registration is refused so the settings row can say so instead of lying.
@MainActor
final class LoginItemController: ObservableObject {
    enum State: Equatable {
        case enabled
        case disabled
        case unavailable(String)
    }

    @Published private(set) var state: State = .disabled

    private let service = SMAppService.mainApp

    func refresh() {
        switch service.status {
        case .enabled: state = .enabled
        case .notRegistered, .notFound: state = .disabled
        case .requiresApproval: state = .disabled
        @unknown default: state = .disabled
        }
    }

    /// Returns the state the switch should show. `nil` means the change landed.
    ///
    /// `SMAppService` hands back an `NSError` in the `SMErrorDomainFramework` domain; the codes
    /// that matter get a sentence the user can act on rather than a framework string.
    func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if service.status == .enabled { return nil }
                try service.register()
            } else {
                if service.status == .notRegistered { return nil }
                try service.unregister()
            }
            refresh()
            return nil
        } catch let error as NSError {
            refresh()
            let message = Self.explanation(for: error)
            state = .unavailable(message)
            Log.lifecycle.error("Login item change failed: \(message, privacy: .public)")
            return message
        }
    }

    private static func explanation(for error: NSError) -> String {
        guard error.domain == "SMErrorDomainFramework" else { return error.localizedDescription }
        // kSMErrorValidationFailure, kSMErrorAlreadyRegistered, kSMErrorFrameworkServicePathsInvalid…
        switch error.code {
        case 404: return "macOS refused the registration. Run PingFlow from a proper .app bundle in /Applications."
        case 405: return "PingFlow is already registered as a login item."
        case 416: return "The app bundle is in a location macOS will not launch from; move it to /Applications."
        default: return error.localizedDescription
        }
    }

    /// macOS 13 keeps a refused registration in Login Items; this is the button that gets there.
    func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.general",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        Log.lifecycle.warning("Could not open the Login Items pane")
    }
}
