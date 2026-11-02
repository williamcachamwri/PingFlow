import AppKit
import CoreGraphics

/// A listen-only `CGEventTap` on its own thread and run loop.
///
/// Two decisions matter here, both taken from the reference's macOS notes:
/// * **Listen-only.** The callback always returns the event untouched, so PingFlow can never
///   swallow a keystroke or a click. Ordinary shortcuts and drags keep working, which is the
///   brief's "must never interfere when the wheel is not being used".
/// * **Its own run loop.** Input is time-critical; a busy main thread must not delay it. The
///   reference runs the tap on a dedicated thread for the same reason, and re-enables the tap
///   when macOS disables it for timing out.
final class EventTap {
    enum Status: Equatable {
        case stopped
        case running
        case noAccess
        case failed(String)
    }

    /// Raw input, already decoded from `CGEvent`. Delivered on the tap thread.
    struct Event: Sendable {
        enum Kind: Sendable {
            case flagsChanged
            case keyDown
            case keyUp
            case mouseDown
            case mouseUp
            case mouseMoved
            case mouseDragged
            case other
        }

        let kind: Kind
        /// Global position in CoreGraphics space: origin top-left of the primary display, y down.
        let location: CGPoint
        let keyCode: UInt16
        let flags: CGEventFlags
        /// 0 left, 1 right, others as macOS numbers them (3 and 4 are the side buttons).
        let mouseButton: Int

        var locationInAppKit: CGPoint { CoordinateSpace.appKitPoint(from: location) }
    }

    private(set) var status: Status = .stopped

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private let stateLock = NSLock()
    private var handler: ((Event) -> Void)?
    private var watchdog: DispatchSourceTimer?

    /// The events the tap must see. Dragged events are included because a held Option plus a
    /// drag does not always produce plain moves.
    private static let mask: CGEventMask =
        (1 << CGEventType.flagsChanged.rawValue)
        | (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.keyUp.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.rightMouseUp.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)
        | (1 << CGEventType.otherMouseUp.rawValue)
        | (1 << CGEventType.mouseMoved.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.rightMouseDragged.rawValue)
        | (1 << CGEventType.otherMouseDragged.rawValue)

    func setHandler(_ handler: @escaping (Event) -> Void) {
        stateLock.lock()
        self.handler = handler
        stateLock.unlock()
    }

    /// Creates the tap. Returns false and sets `.noAccess` when Accessibility has not been
    /// granted; the caller then shows the permission page instead of retrying in a loop.
    @discardableResult
    func start() -> Bool {
        stop()
        guard PermissionManager.isTrusted else {
            setStatus(.noAccess)
            Log.input.warning("Event tap not created: Accessibility is not granted")
            return false
        }
        let pointer = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                       place: .headInsertEventTap,
                                       options: .listenOnly,
                                       eventsOfInterest: Self.mask,
                                       callback: EventTap.callbackThunk,
                                       userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port = pointer else {
            // A stale entry in the Privacy list can make the call return NULL even when the
            // system says we are trusted. Report it once; the Permissions page offers a retry.
            setStatus(.noAccess)
            Log.input.error("CGEventTapCreate returned NULL")
            return false
        }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        setStatus(.running)

        let thread = Thread { [weak self] in
            guard let self, let source = self.source, let port = self.tap else { return }
            let runLoop = CFRunLoopGetCurrent()
            self.stateLock.lock()
            self.runLoop = runLoop
            self.stateLock.unlock()
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            CGEvent.tapEnable(tap: port, enable: true)
            Log.input.info("Event tap run loop started")
            CFRunLoopRun()
            Log.input.info("Event tap run loop ended")
        }
        thread.name = "com.pingflow.eventtap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        startWatchdog()
        return true
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        stateLock.lock()
        let runLoop = self.runLoop
        let source = self.source
        let tap = self.tap
        self.runLoop = nil
        self.source = nil
        self.tap = nil
        self.thread = nil
        stateLock.unlock()
        // Tear the tap down on the run loop that hosts it, then stop that loop.
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }
            CFRunLoopStop(runLoop)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        setStatus(.stopped)
    }

    /// A tap that stops silently would leave the app dead in the water. If the run loop is alive
    /// but no event has arrived for a while, re-enable it — the same cure as the timeout notice.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, let tap = self.tap, self.status == .running else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                Log.input.warning("Event tap was disabled by the system; re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        timer.resume()
        watchdog = timer
    }

    fileprivate func dispatch(type: CGEventType, event: CGEvent) {
        // macOS disables a tap that takes too long. Re-enable it here, as the reference does.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.input.warning("Event tap disabled (\(type.rawValue, privacy: .public)); re-enabled")
            return
        }
        let kind: Event.Kind
        switch type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: kind = .mouseDown
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: kind = .mouseUp
        case .mouseMoved: kind = .mouseMoved
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: kind = .mouseDragged
        default: kind = .other
        }
        let decoded = Event(kind: kind,
                            location: event.location,
                            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                            flags: event.flags,
                            mouseButton: Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        stateLock.lock()
        let handler = self.handler
        stateLock.unlock()
        handler?(decoded)
    }

    private func setStatus(_ status: Status) {
        stateLock.lock()
        self.status = status
        stateLock.unlock()
    }

    var currentStatus: Status {
        stateLock.lock(); defer { stateLock.unlock() }
        return status
    }

    /// For the log line that tells you a tap is running but deaf.
    var isThreadAlive: Bool { thread?.isExecuting ?? false }

    /// C function pointer for CoreGraphics; `userInfo` carries an unretained self.
    private static let callbackThunk: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
        tap.dispatch(type: type, event: event)
        // Listen-only: the event always continues to its original destination.
        return Unmanaged.passUnretained(event)
    }
}

/// Conversions between the two global coordinate spaces the app has to live in.
enum CoordinateSpace {
    /// CoreGraphics: origin at the top-left of the primary display, y down.
    static func cgPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// AppKit: origin at the bottom-left of the primary display, y up.
    static func appKitPoint(from point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }
}
