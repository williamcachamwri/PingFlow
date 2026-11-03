import Foundation

/// An emote the user brought in: one picture — still, moving or video — and optionally a sound.
/// The files live in the library's own folder, never in the app bundle, so an update cannot
/// overwrite them and a reinstall of the bundle keeps every import.
struct CustomEmote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var media: EmoteMedia
    var sound: EmoteSound?
    /// The file name it arrived as, so the library can say where an emote came from.
    var originName: String
    var createdAt: Date

    var key: EmoteKey { .custom(id) }
}

/// The picture half of an import, already normalised down to a size the wheel can draw without
/// paying for it on every frame.
struct EmoteMedia: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        /// A png with alpha. Drawn as one image, like a shipped emote.
        case still
        /// A gif whose frames were re-encoded at the wheel's own size.
        case gif
        /// A video, transcoded small and looped, muted — only the sound slot is ever heard.
        case video
    }

    var kind: Kind
    var fileName: String
    /// A small png of a representative frame: the wheel draws this before the real media is ready.
    var posterFileName: String
    var width: Int
    var height: Int
    var frameCount: Int
    var duration: Double
    var bytes: Int
    /// SHA-256 of the file, so dropping the same art twice does not fill the library.
    var contentHash: String

    var kindLabel: String {
        switch kind {
        case .still: return URL(fileURLWithPath: fileName).pathExtension.uppercased()
        case .gif: return "GIF"
        case .video: return URL(fileURLWithPath: fileName).pathExtension.uppercased()
        }
    }

    var byteLabel: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    var durationLabel: String {
        duration < 1 ? "<1s" : "\(Int((duration * 10).rounded()) / 10)s"
    }
}

/// A sound that came with an import. Nothing is re-encoded: macOS decodes mp3, m4a, wav, ogg,
/// aiff, caf and flac natively, so the file is kept exactly as it arrived.
struct EmoteSound: Codable, Hashable, Sendable {
    var fileName: String
    var duration: Double
    var bytes: Int
    var contentHash: String

    var formatLabel: String { URL(fileURLWithPath: fileName).pathExtension.uppercased() }
    var byteLabel: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
    var durationLabel: String {
        duration < 1 ? "<1s" : "\(Int((duration * 10).rounded()) / 10)s"
    }
}
