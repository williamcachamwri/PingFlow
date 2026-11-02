import AppKit
import PingFlowKit

// PingFlow has no main window and no document type, so the entry point is three lines: a render
// mode for taking the interface's photograph, and the app itself.
if let status = RenderHarness.handleIfRequested(arguments: CommandLine.arguments) {
    exit(status)
}

// Top-level code runs on the main thread, which is what `NSApplication` and the app delegate
// need; `assumeIsolated` says so in the type system instead of fighting it with a dispatch.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
