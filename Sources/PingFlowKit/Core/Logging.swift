import Foundation
import os

/// One logging surface for the whole app. Subsystems match the module boundaries so a log
/// read tells you which layer failed, not just that something did.
enum Log {
    private static let category = "PingFlow"

    static let lifecycle = Logger(subsystem: "com.pingflow.app", category: "lifecycle")
    static let input = Logger(subsystem: "com.pingflow.app", category: "input")
    static let overlay = Logger(subsystem: "com.pingflow.app", category: "overlay")
    static let audio = Logger(subsystem: "com.pingflow.app", category: "audio")
    static let assets = Logger(subsystem: "com.pingflow.app", category: "assets")
    static let settings = Logger(subsystem: "com.pingflow.app", category: "settings")
    static let ui = Logger(subsystem: "com.pingflow.app", category: "ui")
}
