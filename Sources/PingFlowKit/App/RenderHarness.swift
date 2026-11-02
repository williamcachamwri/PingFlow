import AppKit
import SwiftUI

/// A headless render mode, so the interface can be photographed without ever appearing on the
/// user's screen: `PingFlow --render-settings out.png --pane wheel --appearance dark`.
///
/// It builds the real settings view in an off-screen window, waits for its entrance animation to
/// finish, and writes a PNG. That is how the layout gets checked against the reference screenshots
/// on a machine where opening a window would interrupt the work.
public enum RenderHarness {
    /// Returns nil when the arguments are for the ordinary app, so the caller can just launch.
    /// Called from the process entry point, which is the main thread; the work is marked isolated
    /// so the compiler agrees.
    public static func handleIfRequested(arguments: [String]) -> Int32? {
        guard let mode = arguments.first(where: { $0.hasPrefix("--render") || $0 == "--live-wheel" }) else { return nil }
        let options = Options(arguments: arguments)
        return MainActor.assumeIsolated {
            switch mode {
            case "--render-settings": return runSettings(options: options)
            case "--render-wheel": return runWheel(options: options)
            case "--render-ping": return runPing(options: options)
            case "--live-wheel": return runLiveWheel(options: options)
            default:
                FileHandle.standardError.write(Data("Unknown render mode \(mode)\n".utf8))
                return 64
            }
        }
    }

    struct Options {
        let output: URL
        let pane: String
        let appearance: String
        /// The size the caller asked for, or nil when it did not ask.
        let explicitSize: CGSize?
        let size: CGSize
        let wheelSize: CGFloat
        let ping: String
        /// How long the animation runs before the frame is taken. `--render-ping` defaults to 0.35 s;
        /// sweeping it is how a delayed layer that parks in the wrong state gets caught.
        let settle: TimeInterval

        init(arguments: [String]) {
            func value(for flag: String) -> String? {
                guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
                return arguments[index + 1]
            }
            output = URL(fileURLWithPath: value(for: "--out")
                ?? value(for: "-o")
                ?? (arguments.first(where: { $0.hasSuffix(".png") }) ?? "render.png"))
            pane = value(for: "--pane") ?? "general"
            appearance = value(for: "--appearance") ?? "dark"
            explicitSize = {
                guard let raw = value(for: "--size") else { return nil }
                let parts = raw.lowercased().split(separator: "x")
                guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
                return CGSize(width: CGFloat(w), height: CGFloat(h))
            }()
            size = explicitSize ?? CGSize(width: 980, height: 660)
            wheelSize = CGFloat(Double(value(for: "--wheel-size") ?? "460") ?? 460)
            ping = value(for: "--ping") ?? "danger"
            settle = TimeInterval(value(for: "--settle") ?? "0.35") ?? 0.35
        }
    }

    // MARK: - Settings

    @MainActor
    private static func runSettings(options: Options) -> Int32 {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        // An isolated settings file: a render must never touch the user's real settings.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PingFlowRender", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsStore(in: directory)
        store.update {
            $0.appearanceMode = options.appearance == "light" ? .light : .dark
            if options.appearance == "system" { $0.appearanceMode = .system }
        }
        let engine = PingFlowEngine(store: store)

        guard let pane = SettingsPane(rawValue: normalizedPane(options.pane)) else {
            FileHandle.standardError.write(Data("Unknown pane \(options.pane)\n".utf8))
            return 64
        }
        SettingsRouter.shared.open(pane)

        let root = SettingsRootView()
            .environmentObject(store)
            .environmentObject(engine)
            .environmentObject(SettingsRouter.shared)
            .environmentObject(engine.scene)
            .environmentObject(engine.permissions)
            .environmentObject(engine.audio)
            .environmentObject(engine.loginItems)
            .preferredColorScheme(store.settings.appearanceMode.colorScheme)
            .frame(width: options.size.width, height: options.size.height)

        return capture(root: AnyView(root),
                       size: options.size,
                       appearance: store.settings.appearanceMode,
                       to: options.output)
    }

    private static func normalizedPane(_ raw: String) -> String {
        switch raw.lowercased() {
        case "general", "1": return "general"
        case "interaction", "2": return "interaction"
        case "wheel", "pingwheel", "ping-wheel", "3": return "pingWheel"
        case "sounds", "sound", "4": return "sounds"
        case "appearance", "5": return "appearance"
        case "permissions", "permission", "6": return "permissions"
        case "about", "7": return "about"
        default: return raw
        }
    }

    // MARK: - The wheel on its own

    @MainActor
    private static func runWheel(options: Options) -> Int32 {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let side = max(320, min(900, options.wheelSize)) + 80
        let view = PingWheelView(slots: PingDefinition.defaultWheel,
                                 hoveredSlice: 0,
                                 size: side - 80,
                                 centreText: "Danger")
            .frame(width: side, height: side)
            .background(Color(hex: "#0B0B0C"))
        return capture(root: AnyView(view), size: CGSize(width: side, height: side),
                       appearance: .dark, to: options.output)
    }

    /// Presents the real wheel in the real overlay window at the current pointer, photographs that
    /// window, then takes it away. `--render-wheel` proves the view draws; this proves the panel
    /// shows it, which is the half no off-screen render can check.
    @MainActor
    private static func runLiveWheel(options: Options) -> Int32 {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PingFlowRender", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsStore(in: directory)
        let scene = WheelScene()
        let emoteScene = EmoteScene()
        let overlay = OverlayController(scene: scene, emoteScene: emoteScene, store: store)

        let point = CoordinateSpace.cgPoint(fromAppKit: NSEvent.mouseLocation)
        overlay.presentWheel(at: point)
        scene.open(at: point, settings: store.settings)
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))

        guard let (panel, host) = overlay.debugWheelPanel() else {
            FileHandle.standardError.write(Data("No overlay panel is carrying the wheel.\n".utf8))
            overlay.hideEverything()
            return 70
        }
        let report = "phase=\(scene.phase) centre=\(host.wheelCentre) canvas=\(host.canvasSize) "
            + "panelVisible=\(panel.isVisible) alpha=\(panel.alphaValue) level=\(panel.level.rawValue) "
            + "panelFrame=\(panel.frame) contentFrame=\(panel.contentView?.frame ?? .zero) "
            + "opacity=\(scene.overlayOpacity) size=\(scene.size)"
        FileHandle.standardError.write(Data((report + "\n").utf8))

        guard let content = panel.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            FileHandle.standardError.write(Data("Could not photograph the overlay panel.\n".utf8))
            overlay.hideEverything()
            return 70
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        // The panel is transparent everywhere but the wheel, and a transparent PNG tells nobody
        // anything, so flatten it over a mid grey before writing.
        guard let flat = NSBitmapImageRep(bitmapDataPlanes: nil,
                                          pixelsWide: rep.pixelsWide,
                                          pixelsHigh: rep.pixelsHigh,
                                          bitsPerSample: 8,
                                          samplesPerPixel: 4,
                                          hasAlpha: true,
                                          isPlanar: false,
                                          colorSpaceName: .deviceRGB,
                                          bytesPerRow: 0,
                                          bitsPerPixel: 0) else {
            overlay.hideEverything()
            return 70
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: flat)
        NSColor(calibratedWhite: 0.32, alpha: 1).set()
        NSBezierPath(rect: NSRect(origin: .zero, size: flat.size)).fill()
        rep.draw(in: NSRect(origin: .zero, size: flat.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = flat.representation(using: .png, properties: [:]) else {
            overlay.hideEverything()
            return 70
        }
        try? data.write(to: options.output, options: .atomic)
        print("wrote \(options.output.path)")
        overlay.hideEverything()
        return 0
    }

    @MainActor
    private static func runPing(options: Options) -> Int32 {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        guard let definition = PingDefinition.all.first(where: { $0.id.rawValue == options.ping }) else {
            FileHandle.standardError.write(Data(("Unknown ping \"\(options.ping)\" — try one of "
                + PingDefinition.all.map(\.id.rawValue).joined(separator: ", ") + "\n").utf8))
            return 64
        }
        let stage = PingStage()
        var settings = AppSettings()
        settings.pingSize = 160
        settings.pingDuration = 3.2
        // The canvas has to be roomier than the ping, or the frame proves nothing about position.
        let size = options.explicitSize ?? CGSize(width: 640, height: 520)
        let point = CGPoint(x: size.width / 2, y: size.height / 2)
        _ = stage.spawn(definition: definition, at: point, settings: settings)
        let view = ZStack {
            Color(hex: "#101512")
            CrosshairGuide(centre: point, canvasHeight: size.height)
                .allowsHitTesting(false)
            PingFxHost(stage: stage, canvasHeight: size.height)
        }
        .frame(width: size.width, height: size.height)
        let status = capture(root: AnyView(view), size: size, appearance: .dark, to: options.output,
                             settle: options.settle)
        Log.ui.notice("Rendered a \(definition.name, privacy: .public) ping frame")
        return status
    }

    // MARK: - The capture

    /// Puts the view in an off-screen window, lets its entrance finish, then caches the pixels.
    @MainActor
    private static func capture(root: AnyView, size: CGSize, appearance: AppearanceMode,
                                to url: URL, settle: TimeInterval = 1.0) -> Int32 {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Borderless, so the frame, the content rect and the capture rect are the same box. A
        // titled window would add a titlebar's height under the page and cut the footer off.
        window.setFrame(NSRect(x: -4_000, y: -4_000, width: size.width, height: size.height), display: false)
        switch appearance {
        case .system: window.appearance = nil
        case .light: window.appearance = NSAppearance(named: .aqua)
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView?.addSubview(hosting)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayAllocationCycleIfNeeded()

        // The entrance animations are on the clock, not on the capture, so let them finish first.
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: NSRect(origin: .zero, size: size)) else {
            FileHandle.standardError.write(Data("Could not create a bitmap for the render\n".utf8))
            return 70
        }
        hosting.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("Could not encode the render as PNG\n".utf8))
            return 70
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Could not write \(url.path): \(error.localizedDescription)\n".utf8))
            return 73
        }
        print("wrote \(url.path) (\(size.width)×\(size.height) @2x)")
        return 0
    }
}

/// Marks the point the ping was spawned at, so a rendered frame can be measured against it.
/// Debug scaffolding for `--render-ping`; the overlay never draws one.
private struct CrosshairGuide: View {
    let centre: CGPoint
    let canvasHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            // SwiftUI's canvas is y-down; the point came from the stage in the same space.
            let y = centre.y
            var cross = Path()
            cross.move(to: CGPoint(x: 0, y: y))
            cross.addLine(to: CGPoint(x: size.width, y: y))
            cross.move(to: CGPoint(x: centre.x, y: 0))
            cross.addLine(to: CGPoint(x: centre.x, y: size.height))
            context.stroke(cross, with: .color(.green.opacity(0.45)), lineWidth: 1)
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - 3, y: y - 3, width: 6, height: 6)),
                           with: .color(.green), lineWidth: 1.5)
        }
    }
}

private extension NSView {
    /// Forces a display pass so the first `cacheDisplay` has content, without showing the window.
    func displayAllocationCycleIfNeeded() {
        needsDisplay = true
        displayIgnoringIfNeeded()
    }

    private func displayIgnoringIfNeeded() {
        if let window { window.displayIfNeeded() } else { displayIfNeeded() }
    }
}
