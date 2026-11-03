import AVFoundation
import AppKit
import XCTest
@testable import PingFlowKit

/// Everything a custom emote touches: the key a slot holds, the manifest that remembers an import,
/// and the maths the importer does so a dropped file is small enough to fire at 60 fps.
@MainActor
final class CustomEmoteTests: XCTestCase {
    private var scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PingFlowEmoteTests-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Keys

    /// A slot writes as a bare string, so a settings file from before imports still reads.
    func testKeyEncodesAsABareString() throws {
        XCTAssertEqual(encode(EmoteKey.shipped(.poro_snax)), "\"poro_snax\"")
        XCTAssertEqual(encode(EmoteKey.custom("ABC123")), "\"custom:ABC123\"")
        XCTAssertEqual(try JSONDecoder.pingflow.decode(EmoteKey.self, from: Data("\"poro_snax\"".utf8)),
                       EmoteKey.shipped(.poro_snax))
        XCTAssertEqual(try JSONDecoder.pingflow.decode(EmoteKey.self, from: Data("\"custom:ABC123\"".utf8)),
                       EmoteKey.custom("ABC123"))
    }

    func testUnknownKeyIsNotAKey() {
        XCTAssertNil(EmoteKey(rawValue: "not_an_emote"))
        XCTAssertNil(EmoteKey(rawValue: "custom:"))
        XCTAssertNil(EmoteKey(rawValue: ""))
    }

    /// An unreadable slot list costs that one field, not the whole file.
    func testLegacyAndBrokenSettingsBothLoad() throws {
        let legacy = Data(#"{"emoteClick":"poro_snax","emoteWheelSlots":["unworthy_cn","poro_snax"]}"#.utf8)
        let loaded = try JSONDecoder.pingflow.decode(AppSettings.self, from: legacy).normalized()
        XCTAssertEqual(loaded.emoteClick, .shipped(.poro_snax))
        XCTAssertEqual(loaded.emoteWheelSlots.count, 8, "the short list is topped up")
        XCTAssertEqual(loaded.emoteWheelSlots[0], .shipped(.unworthy_cn))

        let imported = Data(#"{"emoteClick":"custom:37B8","emoteWheelSlots":["custom:D089","custom:2E45","poro_snax"]}"#.utf8)
        let carried = try JSONDecoder.pingflow.decode(AppSettings.self, from: imported).normalized()
        XCTAssertEqual(carried.emoteClick, .custom("37B8"), "an import survives the same trip as a shipped name")
        XCTAssertEqual(carried.emoteWheelSlots[0], .custom("D089"))
        XCTAssertEqual(carried.emoteWheelSlots[1], .custom("2E45"))
        XCTAssertEqual(carried.emoteWheelSlots[2], .shipped(.poro_snax))
        XCTAssertEqual(carried.emoteWheelSlots.count, 8)

        var mixed = AppSettings()
        mixed.emoteWheelSlots = [.custom("A"), .custom("B"), .custom("A")] + EmoteDefinition.defaultWheel
        let saved = mixed.normalized()
        XCTAssertEqual(saved.emoteWheelSlots[0], .custom("A"))
        XCTAssertEqual(Set(saved.emoteWheelSlots).count, 8, "a wheel never holds the same emote twice")
    }

    // MARK: - Wheel editing

    func testPlaceAndEvict() {
        let wheel = EmoteDefinition.defaultWheel
        let imported = WheelEditorPlace(wheel)
        XCTAssertEqual(imported[3], .custom("K"), "a drop from the library replaces the occupant")
        XCTAssertEqual(imported.count, 8)
        XCTAssertTrue(EmoteWheelEditor.isValid(imported))

        let evicted = EmoteWheelEditor.evict(imported, .custom("K"))
        XCTAssertFalse(evicted.contains(.custom("K")))
        XCTAssertTrue(EmoteWheelEditor.isValid(evicted), "the hole is refilled, not left dead")
        XCTAssertEqual(EmoteWheelEditor.evict(evicted, .custom("K")), evicted, "evicting twice changes nothing")
    }

    private func WheelEditorPlace(_ wheel: [EmoteKey]) -> [EmoteKey] {
        EmoteWheelEditor.place(wheel, emote: .custom("K"), at: 3) ?? wheel
    }

    // MARK: - The manifest

    func testManifestRoundTripAndDelete() throws {
        let directory = scratch.appendingPathComponent("Library", isDirectory: true)
        let library = EmoteLibrary(directory: directory)
        XCTAssertEqual(library.imported.count, 0)
        XCTAssertNil(library.fileIssue)

        let folder = library.folder(for: "EM1")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([0x00]).write(to: folder.appendingPathComponent("art.gif"))
        try Data([0x00]).write(to: folder.appendingPathComponent("poster.png"))
        library.add(CustomEmote(id: "EM1", name: "Poro Snax",
                                media: media(), sound: nil,
                                originName: "poro.gif", createdAt: Date()))
        library.add(CustomEmote(id: "EM2", name: "Poro Snax",
                                media: media(hash: "other"), sound: nil,
                                originName: "poro2.gif", createdAt: Date()))
        XCTAssertEqual(library.imported.map(\.name), ["Poro Snax", "Poro Snax 2"], "names are made unique")

        let reopened = EmoteLibrary(directory: directory)
        XCTAssertEqual(reopened.imported.map(\.id), ["EM1", "EM2"])
        let asset = reopened.asset(for: .custom("EM1"))
        XCTAssertEqual(asset?.name, "Poro Snax")
        XCTAssertEqual(asset?.mediaURL?.lastPathComponent, "art.gif")
        XCTAssertEqual(asset?.posterURL?.lastPathComponent, "poster.png")
        XCTAssertNil(asset?.soundURL, "a silent import asks for no sound file")
        XCTAssertTrue(reopened.isUsable(reopened.importedEmote("EM1")!),
                      "the art is on disk where the manifest says it is")
        XCTAssertFalse(reopened.holds(mediaHash: "nope"))
        XCTAssertTrue(reopened.holds(mediaHash: media().contentHash))

        _ = reopened.remove("EM1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "its folder goes with it")
        XCTAssertNil(EmoteLibrary(directory: directory).importedEmote("EM1"))
    }

    func testFilesGoneIsNotACrash() {
        let library = EmoteLibrary(directory: scratch.appendingPathComponent("Empty", isDirectory: true))
        library.add(CustomEmote(id: "GONE", name: "Ghost", media: media(), sound: nil,
                               originName: "ghost.gif", createdAt: Date()))
        XCTAssertFalse(library.isUsable(library.importedEmote("GONE")!),
                       "an import whose files were deleted says so instead of drawing a hole")
        // The wheel can still ask for it: the manifest keeps pointing at the folder, and the
        // poster loader returns nothing rather than throwing.
        XCTAssertEqual(library.asset(for: .custom("GONE"))?.mediaURL?.lastPathComponent, "art.gif")
        XCTAssertNil(library.poster(for: library.asset(for: .custom("GONE"))!))
        // A key nothing imports under is simply empty.
        XCTAssertNil(library.asset(for: .custom("NEVER")))
        XCTAssertEqual(library.name(for: .custom("NEVER")), "Empty")
    }

    // MARK: - Detection

    func testClassifyTrustsBytesOverNames() throws {
        XCTAssertEqual(EmoteImporter.classify(try write(named: "lie.png", bytes: gif(header: 3))), .gif)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "picture.mp4", bytes: pngBytes())), .image)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "song", bytes: tag("ID3"))), .audio)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "take.dat", bytes: riff("WAVE"))), .audio)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "sticker.dat", bytes: riff("WEBP"))), .image)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "lossless.goo", bytes: tag("fLaC"))), .audio)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "clip.mov", bytes: ftyp(brand: "M4A "))), .audio)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "clip.png", bytes: ftyp(brand: "isom"))), .video)
        XCTAssertEqual(EmoteImporter.classify(try write(named: "notes.txt", bytes: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])), .unknown)
    }

    // MARK: - Media normalisation

    func testStillIsRedrawnAtTheWheelSize() async throws {
        let source = try writePNG(side: 1200)
        let folder = scratch.appendingPathComponent("still", isDirectory: true)
        let media = try await EmoteImporter.makeMedia(from: source, into: folder)
        XCTAssertEqual(media.kind, .still)
        XCTAssertEqual(media.fileName, "art.png")
        XCTAssertEqual(media.posterFileName, "art.png")
        XCTAssertEqual(max(media.width, media.height), EmoteImporter.maxMediaSide)
        XCTAssertEqual(media.frameCount, 1)
        XCTAssertEqual(media.contentHash.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("art.png").path))
    }

    func testGIFKeepsItsFramesAndItsLoop() async throws {
        let source = try writeGIF(frames: 6, delay: 0.1)
        let folder = scratch.appendingPathComponent("gif", isDirectory: true)
        let media = try await EmoteImporter.makeMedia(from: source, into: folder)
        XCTAssertEqual(media.kind, .gif)
        XCTAssertEqual(media.fileName, "art.gif")
        XCTAssertEqual(media.posterFileName, "poster.png")
        XCTAssertEqual(media.frameCount, 6, "a short loop is not sampled")
        XCTAssertEqual(media.duration, 0.6, accuracy: 0.05)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("poster.png").path))
    }

    func testGIFFramesAreSampledWithoutLosingTime() async throws {
        let source = try writeGIF(frames: 60, delay: 0.05)
        let folder = scratch.appendingPathComponent("biggif", isDirectory: true)
        let media = try await EmoteImporter.makeMedia(from: source, into: folder)
        XCTAssertEqual(media.frameCount, EmoteImporter.maxGIFFrames)
        XCTAssertEqual(media.duration, 3.0, accuracy: 0.2, "the loop still lasts as long as the original")
    }

    /// A hot slice has to draw the gif itself: the poster PNG beside it is one frozen frame, and an
    /// image view cannot animate a picture that has no frames to animate.
    func testAnAnimatingGIFDrawsItsOwnFile() async throws {
        let library = EmoteLibrary(directory: scratch.appendingPathComponent("Anim", isDirectory: true))
        let folder = library.folder(for: "ANIM")
        let media = try await EmoteImporter.makeMedia(from: try writeGIF(frames: 4, delay: 0.1), into: folder)
        library.add(CustomEmote(id: "ANIM", name: "Loop", media: media, sound: nil,
                                originName: "loop.gif", createdAt: Date()))
        let asset = try XCTUnwrap(library.asset(for: .custom("ANIM")))

        let moving = try XCTUnwrap(library.artwork(for: asset, animates: true))
        let resting = try XCTUnwrap(library.artwork(for: asset, animates: false))
        let frames = (moving.representations.first as? NSBitmapImageRep)?
            .value(forProperty: .frameCount) as? NSNumber
        XCTAssertGreaterThan(frames?.intValue ?? 1, 1, "the cell that moves gets the gif's frames")
        XCTAssertNil((resting.representations.first as? NSBitmapImageRep)?
                        .value(forProperty: .frameCount), "a resting cell shows the poster")
    }

    func testEvenSampleSplitsIntoRunsAndCarriesTheirDelay() {
        let frames = (0..<10).map { _ in pngImage(side: 2) }
        let delays = Array(repeating: 0.1, count: 10)
        let sampled = EmoteImporter.evenSample(frames: frames, delays: delays, limit: 5)
        XCTAssertEqual(sampled.frames.count, 5)
        XCTAssertEqual(sampled.delays.reduce(0, +), 1.0, accuracy: 0.001)
        let untouched = EmoteImporter.evenSample(frames: Array(frames.prefix(3)), delays: Array(delays.prefix(3)), limit: 5)
        XCTAssertEqual(untouched.frames.count, 3, "under the cap nothing is dropped")
    }

    // MARK: - Sound

    func testSoundIsCopiedNotConverted() throws {
        let source = try writeWAV(seconds: 0.25)
        let folder = scratch.appendingPathComponent("sound", isDirectory: true)
        let sound = try EmoteImporter.makeSound(from: source, into: folder)
        XCTAssertEqual(sound.fileName, "sound.wav", "the bytes travel as they arrived")
        XCTAssertEqual(sound.duration, 0.25, accuracy: 0.02)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("sound.wav")).count,
                       try Data(contentsOf: source).count)
    }

    /// The point the user asked to keep out of the app: no video is ever turned into a sound,
    /// because that would need a binary another Mac may not have.
    func testAVisualIsRefusedAsASound() throws {
        let picture = try writePNG(side: 40)
        do {
            _ = try EmoteImporter.makeSound(from: picture,
                                            into: scratch.appendingPathComponent("no", isDirectory: true))
            XCTFail("a picture is not a sound")
        } catch let error as EmoteImportError {
            XCTAssertEqual(error, .notASound)
        }
    }

    func testAudioIsRefusedAsArt() async throws {
        let song = try writeWAV(seconds: 0.1)
        do {
            _ = try await EmoteImporter.makeMedia(from: song,
                                                 into: scratch.appendingPathComponent("no2", isDirectory: true))
            XCTFail("a sound belongs on the sound row")
        } catch let error as EmoteImportError {
            guard case .unsupported = error else { return XCTFail("expected unsupported, got \(error)") }
        }
    }

    // MARK: - Helpers

    private func encode(_ key: EmoteKey) -> String {
        let data = try! JSONEncoder.pingflow.encode(key)
        return String(decoding: data, as: UTF8.self)
    }

    private func media(hash: String = "abc123") -> EmoteMedia {
        EmoteMedia(kind: .gif, fileName: "art.gif", posterFileName: "poster.png",
                   width: 128, height: 128, frameCount: 4, duration: 1.2, bytes: 2048,
                   contentHash: hash)
    }

    private func write(named name: String, bytes: [UInt8]) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func pngBytes() -> [UInt8] {
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 16)
    }

    private func gif(header frames: Int) -> [UInt8] {
        Array("GIF89a".utf8) + Array(repeating: UInt8(frames), count: 16)
    }

    private func ftyp(brand: String) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        for (offset, value) in Array("ftyp".utf8).enumerated() { bytes[4 + offset] = value }
        for (offset, value) in Array(brand.utf8).enumerated() { bytes[8 + offset] = value }
        return bytes
    }

    /// A file long enough for the importer to read its magic, with the given four bytes up front.
    private func tag(_ head: String) -> [UInt8] {
        Array(head.utf8) + Array(repeating: 0, count: 24)
    }

    private func riff(_ form: String) -> [UInt8] {
        Array("RIFF".utf8) + [0, 0, 0, 0] + Array(form.utf8) + Array(repeating: 0, count: 16)
    }

    private func pngImage(side: Int) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()!
    }

    @discardableResult
    private func writePNG(side: Int, to name: String? = nil) throws -> URL {
        let url = scratch.appendingPathComponent(name ?? "art-\(side).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, pngImage(side: side), nil)
        guard CGImageDestinationFinalize(destination) else { throw EmoteImportError.unreadable }
        return url
    }

    private func writeGIF(frames: Int, delay: Double) throws -> URL {
        let url = scratch.appendingPathComponent("loop-\(frames).gif")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        for _ in 0..<frames {
            let properties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
            CGImageDestinationAddImage(destination, pngImage(side: 300), properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw EmoteImportError.unreadable }
        return url
    }

    private func writeWAV(seconds: Double, rate: Double = 44100) throws -> URL {
        let url = scratch.appendingPathComponent("sound-\(seconds).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw EmoteImportError.unreadable
        }
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) { samples[index] = sin(Float(index) * 0.05) * 0.3 }
        try file.write(from: buffer)
        return url
    }
}
