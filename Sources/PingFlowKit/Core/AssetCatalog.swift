import AppKit
import AVFoundation

/// Loads the League textures and sounds out of one directory, by name, and remembers what was
/// missing. Nothing else in the app knows where assets live: swap the directory or drop files in
/// and no other module changes.
///
/// Thread-safe behind a lock rather than `@MainActor`, because the audio warm-up decodes wavs on
/// a background queue while the interface asks for the same images on the main one.
final class AssetCatalog {
    static let shared = AssetCatalog()

    struct Check: Identifiable, Hashable {
        enum Kind: String { case texture = "Texture", sound = "Sound" }
        let kind: Kind
        let name: String
        let present: Bool
        var id: String { "\(kind.rawValue):\(name)" }
    }

    private let lock = NSLock()
    private var imageCache: [String: NSImage] = [:]
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private var failedTextures: Set<String> = []
    private var failedSounds: Set<String> = []
    private let searchRoots: [URL]

    /// Directory the files were found in, for the About pane.
    let rootDirectory: URL?

    init(searchRoots: [URL]? = nil) {
        let roots = searchRoots ?? AssetCatalog.defaultSearchRoots()
        // A root only counts when it actually holds the two folders. Under `swift test` the
        // candidate list passes through real directories that have nothing to do with assets,
        // and picking one of those would report "all assets missing" on a healthy install.
        let finder = FileManager.default
        self.searchRoots = roots.filter { AssetCatalog.looksLikeAssetRoot($0, finder: finder) }
        self.rootDirectory = self.searchRoots.first
        Log.assets.info("Asset root: \(self.rootDirectory?.path ?? "none", privacy: .public)")
    }

    private static func looksLikeAssetRoot(_ url: URL, finder: FileManager) -> Bool {
        finder.fileExists(atPath: url.appendingPathComponent("textures").path)
            || finder.fileExists(atPath: url.appendingPathComponent("sounds").path)
            || finder.fileExists(atPath: url.appendingPathComponent("emotes").path)
    }

    /// Bundle resources first (a real launch), then the source tree (a `swift run` from the repo).
    static func defaultSearchRoots() -> [URL] {
        var roots: [URL] = []
        if let override = ProcessInfo.processInfo.environment["PINGFLOW_ASSETS"], !override.isEmpty {
            roots.append(URL(fileURLWithPath: override))
        }
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL.appendingPathComponent("Assets", isDirectory: true))
            roots.append(resourceURL)
        }
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments.first ?? "PingFlow")
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        roots.append(executableDirectory.appendingPathComponent("Assets", isDirectory: true))
        // SPM puts the binary under .build/<config>/; the repo's Assets/ is a few levels up.
        var ancestor = executableDirectory
        for _ in 0..<5 {
            ancestor = ancestor.deletingLastPathComponent()
            roots.append(ancestor.appendingPathComponent("Assets", isDirectory: true))
        }
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets", isDirectory: true))
        return roots
    }

    // MARK: - Textures

    /// The texture as an `NSImage`, or nil when it is not on disk. Cached: the wheel draws the
    /// same eight images on every gesture and the editor redraws them on every hover.
    func image(named name: String) -> NSImage? {
        lock.lock()
        if let cached = imageCache[name] { lock.unlock(); return cached }
        lock.unlock()

        guard let url = fileURL(subdirectory: "textures", name: name, extensions: ["png", "webp", "jpg"]) else {
            markMissing(texture: name)
            return nil
        }
        guard let image = NSImage(contentsOf: url) else {
            markMissing(texture: name)
            Log.assets.error("Could not decode \(name, privacy: .public)")
            return nil
        }
        lock.lock()
        imageCache[name] = image
        lock.unlock()
        return image
    }

    func cgImage(named name: String) -> CGImage? {
        guard let image = image(named: name) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func image(for definition: PingDefinition) -> NSImage? {
        image(named: definition.iconTexture) ?? image(named: PingDefinition.fallbackTexture)
    }

    // MARK: - Sounds

    /// Decodes a wav once into a buffer. Playback then costs nothing: no file IO, no decode.
    func buffer(for soundName: String) -> AVAudioPCMBuffer? {
        lock.lock()
        if let cached = bufferCache[soundName] { lock.unlock(); return cached }
        lock.unlock()

        guard let url = fileURL(subdirectory: "sounds", name: soundName, extensions: ["wav", "mp3", "caf", "aiff"]) else {
            markMissing(sound: soundName)
            return nil
        }
        guard let buffer = AssetCatalog.decodeBuffer(from: url) else {
            markMissing(sound: soundName)
            return nil
        }
        lock.lock()
        bufferCache[soundName] = buffer
        lock.unlock()
        return buffer
    }

    func buffer(for definition: PingDefinition) -> AVAudioPCMBuffer? { buffer(for: definition.sound) }

    // MARK: - Emotes

    func emoteImage(named name: String) -> NSImage? {
        lock.lock()
        let key = "emote:\(name)"
        if let cached = imageCache[key] { lock.unlock(); return cached }
        lock.unlock()

        guard let url = fileURL(subdirectory: "emotes", name: name, extensions: ["png", "webp", "jpg"]) else {
            markMissing(texture: key)
            return nil
        }
        guard let image = NSImage(contentsOf: url) else {
            markMissing(texture: key)
            return nil
        }
        lock.lock()
        imageCache[key] = image
        lock.unlock()
        return image
    }

    func emoteBuffer(named name: String) -> AVAudioPCMBuffer? {
        lock.lock()
        let key = "emote:\(name)"
        if let cached = bufferCache[key] { lock.unlock(); return cached }
        lock.unlock()

        guard let url = fileURL(subdirectory: "emotes", name: name, extensions: ["ogg", "wav", "mp3", "caf"]) else {
            markMissing(sound: key)
            return nil
        }
        guard let buffer = AssetCatalog.decodeBuffer(from: url) else {
            markMissing(sound: key)
            return nil
        }
        lock.lock()
        bufferCache[key] = buffer
        lock.unlock()
        return buffer
    }

    /// Decodes every sound and texture the app can use, off the calling thread, once after launch.
    func preloadAll() async {
        await withTaskGroup(of: Void.self) { group in
            for definition in PingDefinition.all {
                group.addTask { [weak self] in _ = self?.buffer(for: definition.sound) }
                for texture in Set([definition.iconTexture] + definition.artTextures) {
                    group.addTask { [weak self] in _ = self?.image(named: texture) }
                }
            }
            group.addTask { [weak self] in _ = self?.buffer(for: PingDefinition.tickSound) }
            group.addTask { [weak self] in _ = self?.image(named: PingDefinition.logoTexture) }
            for emote in EmoteDefinition.all {
                group.addTask { [weak self] in _ = self?.emoteImage(named: emote.textureName) }
                group.addTask { [weak self] in _ = self?.emoteBuffer(named: emote.soundName) }
            }
        }
    }

    /// Drops cached buffers whose name starts with `prefix`, so the next play reads the file again.
    func forget(prefix: String) {
        lock.lock()
        bufferCache = bufferCache.filter { !$0.key.hasPrefix(prefix) }
        imageCache = imageCache.filter { !$0.key.hasPrefix(prefix) }
        lock.unlock()
    }

    // MARK: - Reporting

    var missingTextures: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return failedTextures
    }

    var missingSounds: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return failedSounds
    }

    /// Every file the app wants, and whether it is there. The About page shows this instead of
    /// failing quietly when someone deletes the asset folder.
    func inventory() -> [Check] {
        var checks: [Check] = []
        for definition in PingDefinition.all {
            for texture in Set([definition.iconTexture] + definition.artTextures) {
                checks.append(Check(kind: .texture, name: texture, present: texturePresent(texture)))
            }
            checks.append(Check(kind: .sound, name: definition.sound, present: soundPresent(definition.sound)))
        }
        checks.append(Check(kind: .sound, name: PingDefinition.tickSound, present: soundPresent(PingDefinition.tickSound)))
        checks.append(Check(kind: .texture, name: PingDefinition.logoTexture, present: texturePresent(PingDefinition.logoTexture)))
        return checks
    }

    var hasEveryAsset: Bool { inventory().allSatisfy(\.present) }

    private func texturePresent(_ name: String) -> Bool {
        fileURL(subdirectory: "textures", name: name, extensions: ["png", "webp", "jpg"]) != nil
    }

    private func soundPresent(_ name: String) -> Bool {
        fileURL(subdirectory: "sounds", name: name, extensions: ["wav", "mp3", "caf", "aiff"]) != nil
    }

    private func markMissing(texture name: String) {
        lock.lock(); failedTextures.insert(name); lock.unlock()
    }

    private func markMissing(sound name: String) {
        lock.lock(); failedSounds.insert(name); lock.unlock()
    }

    private func fileURL(subdirectory: String, name: String, extensions: [String]) -> URL? {
        let finder = FileManager.default
        for root in searchRoots {
            let directory = root.appendingPathComponent(subdirectory, isDirectory: true)
            for ext in extensions {
                let candidate = directory.appendingPathComponent("\(name).\(ext)")
                if finder.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private static func decodeBuffer(from url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else {
            Log.audio.error("Could not open \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        do {
            try file.read(into: buffer)
            return buffer
        } catch {
            Log.audio.error("Decode failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
