import AppKit
import AVFoundation
import Combine
import Foundation

/// One row of the emote library, whether the art shipped with the app or arrived from Finder.
struct EmoteEntry: Identifiable, Hashable {
    let key: EmoteKey
    let name: String
    let category: EmoteCategory
    /// What the slot will draw: `PNG` for a shipped emote, `GIF`/`MP4` for an import.
    let kindLabel: String
    let hasSound: Bool
    let isImported: Bool

    var id: String { key.rawValue }
}

/// Everything needed to draw and hear one emote, with its files already found on disk.
struct EmoteAsset: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case still
        case gif
        case video
    }

    let key: EmoteKey
    let name: String
    let kind: Kind
    /// The art itself. nil when the file is gone, which is what a missing shipped texture means.
    let mediaURL: URL?
    /// A single frame to show while the real media is not on screen yet, and to put in the wheel.
    let posterURL: URL?
    let soundURL: URL?

    var id: String { key.rawValue }

    var isAnimated: Bool { kind != .still }
}

/// The shipped emotes plus whatever the user imported, and the only place that knows where any
/// of their files are. Imports are recorded in one manifest beside their folders.
@MainActor
final class EmoteLibrary: ObservableObject {
    static let shared = EmoteLibrary()

    private static let manifestName = "library.json"

    @Published private(set) var imported: [CustomEmote] = []

    /// Set when the manifest could not be read or written, so the library can say so out loud
    /// instead of quietly losing the next import.
    @Published private(set) var fileIssue: String?

    let directory: URL
    private let manifestURL: URL
    /// A shipped emote resolves by probing the bundle for four extensions, and the grid asks for
    /// all forty-four on every redraw. The bundle never changes while the app runs.
    private var shippedCache: [String: EmoteAsset?] = [:]

    init(directory: URL = AppPaths.emoteLibraryDirectory) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent(Self.manifestName)
        load()
    }

    // MARK: - What is available

    /// Shipped emotes first, newest import last: the order the grid shows.
    var entries: [EmoteEntry] {
        let shipped = EmoteDefinition.all.map { definition in
            EmoteEntry(key: definition.key,
                       name: definition.name,
                       category: definition.category,
                       kindLabel: "PNG",
                       hasSound: AssetCatalog.shared.emoteSoundURL(named: definition.soundName) != nil,
                       isImported: false)
        }
        let mine = imported.map { emote in
            EmoteEntry(key: emote.key,
                       name: emote.name,
                       category: .custom,
                       kindLabel: emote.media.kindLabel,
                       hasSound: emote.sound != nil,
                       isImported: true)
        }
        return shipped + mine
    }

    func importedEmote(_ id: String) -> CustomEmote? {
        imported.first { $0.id == id }
    }

    /// nil only for a key nothing resolves to — an import that was deleted out from under the wheel.
    func asset(for key: EmoteKey) -> EmoteAsset? {
        switch key.kind {
        case .shipped:
            if let cached = shippedCache[key.token] { return cached }
            let resolved = Self.resolveShipped(key)
            shippedCache[key.token] = resolved
            return resolved
        case .custom:
            guard let emote = importedEmote(key.token) else { return nil }
            let folder = folder(for: emote.id)
            return EmoteAsset(key: key,
                              name: emote.name,
                              kind: EmoteAsset.Kind(rawValue: emote.media.kind.rawValue) ?? .still,
                              mediaURL: folder.appendingPathComponent(emote.media.fileName),
                              posterURL: folder.appendingPathComponent(emote.media.posterFileName),
                              soundURL: emote.sound.map { folder.appendingPathComponent($0.fileName) })
        }
    }

    private static func resolveShipped(_ key: EmoteKey) -> EmoteAsset? {
        guard let id = key.shippedID, let definition = EmoteDefinition.allByID[id] else { return nil }
        let texture = AssetCatalog.shared.emoteTextureURL(named: definition.textureName)
        // Someone dropping a gif into the shipped folder gets animation, not a frozen frame.
        let isGIF = texture?.pathExtension.lowercased() == "gif"
        return EmoteAsset(key: key,
                          name: definition.name,
                          kind: isGIF ? .gif : .still,
                          mediaURL: texture,
                          posterURL: texture,
                          soundURL: AssetCatalog.shared.emoteSoundURL(named: definition.soundName))
    }

    func name(for key: EmoteKey) -> String {
        asset(for: key)?.name ?? "Empty"
    }

    /// The image to draw for a slot: the poster for an import, the art itself for a shipped emote.
    func poster(for key: EmoteKey) -> NSImage? {
        if key.kind == .shipped {
            return AssetCatalog.shared.emoteImage(named: key.token)
        }
        guard let asset = asset(for: key) else { return nil }
        return poster(for: asset)
    }

    func poster(for asset: EmoteAsset) -> NSImage? {
        if asset.key.kind == .shipped {
            return AssetCatalog.shared.emoteImage(named: asset.key.token)
        }
        guard let url = asset.posterURL ?? asset.mediaURL else { return nil }
        return AssetCatalog.shared.image(at: url, cacheKey: "import:\(asset.key.token):poster")
    }

    /// What a cell draws. An animating gif must come from its own file — `NSImageView` plays the
    /// frames inside it, and the poster PNG beside it can only ever be one frozen frame. Anything
    /// else, resting or moving, is the poster.
    func artwork(for asset: EmoteAsset, animates: Bool) -> NSImage? {
        guard animates, asset.kind == .gif, let url = asset.mediaURL else { return poster(for: asset) }
        // Keyed under the import so `invalidate` drops it when its art is replaced.
        return AssetCatalog.shared.image(at: url, cacheKey: "import:\(asset.key.token):art")
            ?? poster(for: asset)
    }

    func buffer(for asset: EmoteAsset) -> AVAudioPCMBuffer? {
        if asset.key.kind == .shipped {
            return AssetCatalog.shared.emoteBuffer(named: asset.key.token)
        }
        guard let url = asset.soundURL else { return nil }
        return AssetCatalog.shared.buffer(at: url, cacheKey: "import:\(asset.key.token)")
    }

    func folder(for id: String) -> URL {
        directory.appendingPathComponent(id, isDirectory: true)
    }

    /// True when an import's files are on disk, which the grid shows instead of a broken thumbnail.
    func isUsable(_ emote: CustomEmote) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: emote.id).appendingPathComponent(emote.media.fileName).path)
    }

    var importedBytes: Int {
        imported.reduce(0) { total, emote in
            total + emote.media.bytes + (emote.sound?.bytes ?? 0)
        }
    }

    /// True when the same art is already in the library, so a second drop is a no-op.
    func holds(mediaHash: String) -> Bool {
        imported.contains { $0.media.contentHash == mediaHash }
    }

    func importedEmote(mediaHash: String) -> CustomEmote? {
        imported.first { $0.media.contentHash == mediaHash }
    }

    // MARK: - Mutation

    func add(_ emote: CustomEmote) {
        var next = emote
        next.name = Self.uniqueName(next.name, existing: imported.map(\.name))
        imported.append(next)
        save()
    }

    func update(_ emote: CustomEmote) {
        guard let index = imported.firstIndex(where: { $0.id == emote.id }) else { return }
        imported[index] = emote
        save()
    }

    func rename(_ id: String, to name: String) {
        guard var emote = importedEmote(id) else { return }
        emote.name = Self.clean(name)
        update(emote)
    }

    func setSound(_ id: String, _ sound: EmoteSound?) {
        guard var emote = importedEmote(id) else { return }
        emote.sound = sound
        update(emote)
    }

    /// Deletes an import's folder and returns its key, so the caller can clear the wheel slots
    /// that were pointing at it rather than leave a dead slice.
    @discardableResult
    func remove(_ id: String) -> EmoteKey {
        let key = EmoteKey.custom(id)
        imported.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folder(for: id))
        AssetCatalog.shared.forget(prefix: "import:\(id)")
        save()
        return key
    }

    /// Called after a media or sound file is replaced, so the next draw re-reads the folder.
    func invalidate(_ id: String) {
        AssetCatalog.shared.forget(prefix: "import:\(id)")
        objectWillChange.send()
    }

    // MARK: - Names

    nonisolated static func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(48))
        return cut.isEmpty ? "My emote" : cut
    }

    private nonisolated static func uniqueName(_ name: String, existing: [String]) -> String {
        let base = clean(name)
        guard existing.contains(base) else { return base }
        var counter = 2
        while existing.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    // MARK: - Persistence

    private struct Manifest: Codable {
        var version = 1
        var emotes: [CustomEmote] = []
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder.pingflow.decode(Manifest.self, from: data)
            imported = manifest.emotes
            fileIssue = nil
        } catch {
            fileIssue = "Imported emotes could not be read (\(error.localizedDescription))."
            imported = []
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder.pingflow
            let data = try encoder.encode(Manifest(version: 1, emotes: imported))
            try data.write(to: manifestURL, options: [.atomic])
            fileIssue = nil
        } catch {
            fileIssue = "Imported emotes could not be saved (\(error.localizedDescription))."
        }
    }
}

extension JSONDecoder {
    /// One date strategy for every file the app writes, so a hand-opened json stays readable.
    static let pingflow: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let pingflow: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
