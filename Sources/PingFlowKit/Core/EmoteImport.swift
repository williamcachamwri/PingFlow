import AVFoundation
import CoreServices
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a dropped file actually is, decided from its bytes rather than its name — Finder renames
/// things, cameras lie, and a gif saved as `.dat` is still a gif.
enum EmoteSourceKind: String, Hashable, Sendable {
    case gif
    case image
    case video
    case audio
    case unknown
}

/// An import failure the interface can say out loud.
enum EmoteImportError: Error, Equatable, Sendable {
    case unreadable
    case unsupported(String)
    case tooLarge(megabytes: Int)
    case noVisualTrack
    case fullLibrary(limit: Int)
    case notASound

    var message: String {
        switch self {
        case .unreadable: return "That file could not be read."
        case .unsupported(let detail): return detail
        case .tooLarge(let megabytes): return "Bigger than \(megabytes) MB — trim it first."
        case .noVisualTrack: return "That video has no picture track."
        case .fullLibrary(let limit): return "The library holds \(limit) emotes. Delete one first."
        case .notASound: return "The sound row takes an audio file, not a picture or a clip."
        }
    }
}

/// Turns a file from Finder into art the wheel can draw without paying for it on every frame.
/// Everything here blocks, so callers run it off the main thread: give it a folder that already
/// belongs to the new emote and it writes the art plus a poster into it.
enum EmoteImporter {
    /// Art is never kept bigger than this on its long side. The wheel draws 48 pt icons and the
    /// overlay at most 220 pt, so anything larger only costs decode time and memory.
    static let maxMediaSide = 256
    static let maxGIFFrames = 40
    static let maxVideoSeconds = 6.0
    static let maxMediaBytes = 40 * 1024 * 1024
    static let maxSoundBytes = 12 * 1024 * 1024
    static let libraryCapacity = 240

    // MARK: - Detection

    static func classify(_ url: URL) -> EmoteSourceKind {
        guard let head = try? Data(contentsOf: url, options: [.mappedIfSafe]), head.count > 16 else {
            return extensionKind(url)
        }
        func magic(_ text: String) -> Bool { head.starts(with: Array(text.utf8)) }
        func box(_ offset: Int, _ text: String) -> Bool {
            head.count >= offset + 4 && Array(head[offset..<(offset + 4)]) == Array(text.utf8)
        }
        func brand(_ offset: Int) -> String {
            head.count >= offset + 4 ? String(decoding: head[offset..<(offset + 4)], as: UTF8.self) : ""
        }
        if magic("GIF8") { return .gif }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .image }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return .image }
        if magic("OggS") || magic("ID3") { return .audio }
        if magic("fLaC") { return .audio }
        if magic("RIFF") && box(8, "WEBP") { return .image }
        // RIFF is a container, so the four bytes after it decide whether this is a picture or a
        // recording — a .wav renamed `.dat` is still a sound.
        if magic("RIFF") && box(8, "WAVE") { return .audio }
        if magic("FORM") && box(8, "AIFF") { return .audio }
        if magic("FORM") && box(8, "AIFC") { return .audio }
        // An .m4a and an .mp4 share the container; the brand four bytes after `ftyp` is what tells
        // them apart, and the file extension is a name somebody typed.
        if box(4, "ftyp") { return brand(8).hasPrefix("M4A") ? .audio : .video }
        if head.starts(with: [0x00, 0x00, 0x01, 0xBA]) { return .video }
        if head[0] == 0xFF, head[1] & 0xE0 == 0xE0 { return .audio }
        return extensionKind(url)
    }

    private static func extensionKind(_ url: URL) -> EmoteSourceKind {
        switch url.pathExtension.lowercased() {
        case "gif": return .gif
        case "png", "jpg", "jpeg", "webp", "heic", "tiff", "tif", "bmp": return .image
        case "mp4", "mov", "m4v", "3gp": return .video
        case "mp3", "m4a", "aac", "wav", "ogg", "aiff", "aif", "flac", "caf", "mka": return .audio
        default: return .unknown
        }
    }

    // MARK: - Media

    /// Normalises the art and describes what was written. A still or a gif is re-encoded small; a
    /// video is exported small with a poster and keeps its original bytes only if the exporter
    /// refuses it.
    static func makeMedia(from url: URL, into folder: URL) async throws -> EmoteMedia {
        let bytes = fileSize(of: url)
        guard bytes > 0 else { throw EmoteImportError.unreadable }
        guard bytes <= maxMediaBytes else {
            throw EmoteImportError.tooLarge(megabytes: maxMediaBytes / (1024 * 1024))
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        switch classify(url) {
        case .gif: return try makeGIF(from: url, into: folder)
        case .image: return try makeStill(from: url, into: folder)
        case .video: return try await makeVideo(from: url, into: folder)
        case .audio:
            throw EmoteImportError.unsupported("That is a sound file — drop it on the sound row.")
        case .unknown:
            throw EmoteImportError.unsupported("PingFlow cannot read \(url.pathExtension.uppercased()) files.")
        }
    }

    private static func makeStill(from url: URL, into folder: URL) throws -> EmoteMedia {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw EmoteImportError.unreadable
        }
        let art = resize(first, to: maxMediaSide)
        let fileName = "art.png"
        let written = folder.appendingPathComponent(fileName)
        guard write(art, to: written, type: UTType.png.identifier, count: 1, properties: nil) else {
            throw EmoteImportError.unreadable
        }
        return EmoteMedia(kind: .still,
                          fileName: fileName,
                          posterFileName: fileName,
                          width: art.width,
                          height: art.height,
                          frameCount: 1,
                          duration: 0,
                          bytes: fileSize(of: written),
                          contentHash: sha256(of: written))
    }

    private static func makeGIF(from url: URL, into folder: URL) throws -> EmoteMedia {
        let decoded = try decodeGIF(url)
        guard !decoded.frames.isEmpty else { throw EmoteImportError.unreadable }
        let sampled = evenSample(frames: decoded.frames, delays: decoded.delays, limit: maxGIFFrames)
        let scale = min(1, CGFloat(maxMediaSide) / CGFloat(max(decoded.canvas.width, decoded.canvas.height, 1)))
        let side = CGSize(width: max(1, Int((decoded.canvas.width * scale).rounded())),
                          height: max(1, Int((decoded.canvas.height * scale).rounded())))
        // Every frame is redrawn on the same canvas so the loop cannot shift, whatever the
        // original file did between frames.
        let frames = sampled.frames.map { draw($0, into: side) }

        let fileName = "art.gif"
        let written = folder.appendingPathComponent(fileName)
        guard let destination = CGImageDestinationCreateWithURL(written as CFURL,
                                                               UTType.gif.identifier as CFString,
                                                               frames.count, nil) else {
            throw EmoteImportError.unreadable
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for (index, frame) in frames.enumerated() {
            let properties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: max(0.02, sampled.delays[index])],
            ]
            CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: written)
            throw EmoteImportError.unreadable
        }
        let poster = try writePoster(frames[0], in: folder)
        return EmoteMedia(kind: .gif,
                          fileName: fileName,
                          posterFileName: poster,
                          width: Int(side.width),
                          height: Int(side.height),
                          frameCount: frames.count,
                          duration: sampled.delays.reduce(0, +),
                          bytes: fileSize(of: written),
                          contentHash: sha256(of: written))
    }

    private static func makeVideo(from url: URL, into folder: URL) async throws -> EmoteMedia {
        let asset = AVURLAsset(url: url)
        // Reading a clip's values one at a time is how AVFoundation worked before macOS 13, and an
        // import is already off the main thread, so the awaits cost the interface nothing.
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard let track = tracks.first else { throw EmoteImportError.noVisualTrack }
        let seconds = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)
        guard seconds > 0, seconds < 3600 else { throw EmoteImportError.unreadable }
        let cap = CMTimeRange(start: .zero,
                              duration: CMTime(seconds: min(seconds, maxVideoSeconds),
                                               preferredTimescale: 600))
        let fileName = "art.mp4"
        let written = folder.appendingPathComponent(fileName)
        var exported = false
        if let session = exportSession(for: asset, to: written) {
            session.timeRange = cap
            // `exportAsynchronously` is the only form without a completion handler, and the wait
            // is there because a corrupt stream can otherwise stall the export forever.
            session.exportAsynchronously {}
            exported = await awaitExport(session)
        }
        if !exported {
            try? FileManager.default.removeItem(at: written)
            do { try FileManager.default.copyItem(at: url, to: written) } catch {
                throw EmoteImportError.unreadable
            }
        }

        let loaded = try? await track.load(.naturalSize, .preferredTransform)
        guard let (size, transform) = loaded else { throw EmoteImportError.unreadable }
        let natural = CGSizeApplyAffineTransform(size, transform)
        guard let posterFrame = posterFrame(from: asset, at: cap) else {
            throw EmoteImportError.unreadable
        }
        let poster = try writePoster(posterFrame, in: folder)
        return EmoteMedia(kind: .video,
                          fileName: fileName,
                          posterFileName: poster,
                          width: max(1, Int(abs(natural.width).rounded())),
                          height: max(1, Int(abs(natural.height).rounded())),
                          frameCount: 1,
                          duration: min(seconds, maxVideoSeconds),
                          bytes: fileSize(of: written),
                          contentHash: sha256(of: written))
    }

    /// The smallest preset this clip will take. Building a session is the compatibility test: the
    /// initialiser returns nil for a preset the media cannot export, and the list API that used to
    /// answer the question is gone.
    private static func exportSession(for asset: AVAsset, to written: URL) -> AVAssetExportSession? {
        for preset in [AVAssetExportPreset640x480, AVAssetExportPreset960x540,
                       AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality] {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            session.outputURL = written
            session.outputFileType = .mp4
            session.shouldOptimizeForNetworkUse = true
            return session
        }
        return nil
    }

    private static func awaitExport(_ session: AVAssetExportSession) async -> Bool {
        let deadline = Date().addingTimeInterval(60)
        while session.status == .waiting || session.status == .exporting {
            if Date() > deadline {
                session.cancelExport()
                return false
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if let error = session.error {
            Log.assets.error("Video export failed: \(error.localizedDescription, privacy: .public)")
        }
        return session.status == .completed
    }

    private static func posterFrame(from asset: AVAsset, at range: CMTimeRange) -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxMediaSide, height: maxMediaSide)
        let second = CMTimeAdd(range.start, CMTime(seconds: 0.1, preferredTimescale: 600))
        guard let image = try? generator.copyCGImage(at: second, actualTime: nil) else { return nil }
        return resize(image, to: maxMediaSide)
    }

    // MARK: - Sound

    /// A sound is kept exactly as it arrived: macOS decodes mp3, m4a, wav, ogg, aiff, caf and flac
    /// natively, so re-encoding would cost quality and a helper binary nobody guarantees to have.
    static func makeSound(from url: URL, into folder: URL) throws -> EmoteSound {
        let bytes = fileSize(of: url)
        guard bytes > 0 else { throw EmoteImportError.unreadable }
        guard classify(url) == .audio else { throw EmoteImportError.notASound }
        guard bytes <= maxSoundBytes else {
            throw EmoteImportError.tooLarge(megabytes: maxSoundBytes / (1024 * 1024))
        }
        let ext = url.pathExtension.lowercased().isEmpty ? "caf" : url.pathExtension.lowercased()
        let fileName = "sound.\(ext)"
        let written = folder.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: written)
        do { try FileManager.default.copyItem(at: url, to: written) } catch {
            throw EmoteImportError.unreadable
        }
        guard let file = try? AVAudioFile(forReading: written) else {
            try? FileManager.default.removeItem(at: written)
            throw EmoteImportError.unsupported("That audio codec cannot be played.")
        }
        let format = file.processingFormat
        let seconds = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
        return EmoteSound(fileName: fileName,
                          duration: seconds,
                          bytes: fileSize(of: written),
                          contentHash: sha256(of: written))
    }

    // MARK: - GIF decoding

    struct GIFDecoded {
        let frames: [CGImage]
        let delays: [Double]
        let canvas: CGSize
    }

    static func decodeGIF(_ url: URL) throws -> GIFDecoded {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw EmoteImportError.unreadable
        }
        let count = CGImageSourceGetCount(source)
        var frames: [CGImage] = []
        var delays: [Double] = []
        var canvas = CGSize(width: 1, height: 1)
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let properties = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
            let gif = (properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]) ?? [:]
            if index == 0 {
                let width = (gif[kCGImagePropertyGIFCanvasPixelWidth] as? Int)
                    ?? (properties[kCGImagePropertyWidth] as? Int) ?? image.width
                let height = (gif[kCGImagePropertyGIFCanvasPixelHeight] as? Int)
                    ?? (properties[kCGImagePropertyHeight] as? Int) ?? image.height
                canvas = CGSize(width: max(1, width), height: max(1, height))
            }
            let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0
            let clamped = (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
            delays.append(unclamped > 0 ? unclamped : clamped)
            frames.append(image)
        }
        return GIFDecoded(frames: frames, delays: delays, canvas: canvas)
    }

    /// Keeps the loop's total length while dropping the frames that would not be missed: the
    /// animation is cut into `limit` runs, the first frame of each run survives, and it carries
    /// the combined delay of every frame it replaced.
    static func evenSample(frames: [CGImage], delays: [Double], limit: Int) -> (frames: [CGImage], delays: [Double]) {
        let count = frames.count
        guard count > limit, limit > 0 else { return (frames, Array(delays.prefix(count))) }
        var picked: [CGImage] = []
        var pickedDelays: [Double] = []
        var start = 0
        for chunk in 0..<limit {
            let next = max(min(count, ((chunk + 1) * count) / limit), start + 1)
            var total = 0.0
            for index in start..<next {
                total += index < delays.count ? delays[index] : 0
            }
            picked.append(frames[start])
            pickedDelays.append(max(0.02, total))
            start = next
        }
        return (picked, pickedDelays)
    }

    // MARK: - Drawing helpers

    private static func resize(_ image: CGImage, to side: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > side else { return image }
        let scale = CGFloat(side) / CGFloat(longest)
        let size = CGSize(width: max(1, Int((CGFloat(image.width) * scale).rounded())),
                          height: max(1, Int((CGFloat(image.height) * scale).rounded())))
        return draw(image, into: size)
    }

    private static func draw(_ image: CGImage, into size: CGSize) -> CGImage {
        guard let context = bitmapContext(width: Int(size.width), height: Int(size.height)) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage() ?? image
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func write(_ image: CGImage, to url: URL, type: String, count: Int,
                              properties: [CFString: Any]?) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, count, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        return CGImageDestinationFinalize(destination)
    }

    private static func writePoster(_ image: CGImage, in folder: URL) throws -> String {
        let fileName = "poster.png"
        guard write(resize(image, to: maxMediaSide),
                    to: folder.appendingPathComponent(fileName),
                    type: UTType.png.identifier, count: 1, properties: nil) else {
            throw EmoteImportError.unreadable
        }
        return fileName
    }

    // MARK: - File facts

    static func fileSize(of url: URL) -> Int {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
    }

    static func sha256(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A tidy label for a file name: no extension, no underscores, not absurdly long.
    static func suggestedName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let spaced = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return EmoteLibrary.clean(spaced)
    }
}
