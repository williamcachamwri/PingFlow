import AVFoundation
import CoreAudio
import Combine

/// Polyphonic playback with no per-play cost: every sound is decoded once into an
/// `AVAudioPCMBuffer`, and each voice is a pre-attached `AVAudioPlayerNode` that only gets
/// `scheduleBuffer` called on it. That is the native equivalent of the reference's
/// AudioBufferSource-per-play route, which is what removed the delay they measured with
/// `HTMLAudioElement`.
///
/// The graph is built lazily, and only when the Mac actually has an output device. Calling
/// `prepare()` on a process without one raises an Objective-C exception inside AVFAudio that
/// Swift cannot catch — it would take the app down at launch on a headless machine, in the
/// render harness, or after someone unplugs the only speaker.
@MainActor
final class AudioEngine: ObservableObject {
    /// More overlapping voices than this are skipped — the ping still shows, the audio just
    /// does not pile up into distortion during a flood.
    static let voicePoolSize = 8

    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var busy: [Bool] = []
    private var started = false
    private var graphIsReady = false
    private var graphFormat: AVAudioFormat?
    /// Sounds resampled to the output device's format, cached so the conversion happens once.
    private var readyBuffers: [String: AVAudioPCMBuffer] = [:]
    private var masterVolume: Float = 0.7
    private var settingsToken: AnyCancellable?

    /// False when this Mac has no usable audio output. The Sounds page can say so instead of
    /// playing silence and leaving the user to guess.
    private(set) var isAvailable = true

    init() {
        // Deliberately empty: see `buildGraph()`. Constructing the engine must never touch hardware.
    }

    /// Follows the settings store, so volume and mute apply the moment the user moves a slider.
    func bind(to store: SettingsStore) {
        settingsToken = store.$settings.sink { [weak self] settings in
            self?.masterVolume = settings.isMuted ? 0 : Float(settings.volume)
        }
    }

    // MARK: - Graph

    /// Attaches the eight voices and wires them to the mixer. Idempotent, so it can be called on
    /// every play until the first one that finds a device.
    private func buildGraph() -> Bool {
        if graphIsReady { return true }
        guard Self.hasOutputDevice() else {
            isAvailable = false
            Log.audio.warning("No audio output device; pings will be silent")
            return false
        }
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            isAvailable = false
            Log.audio.warning("The default output device reports an unusable format")
            return false
        }
        graphFormat = format
        for _ in 0..<Self.voicePoolSize {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes.append(node)
            busy.append(false)
        }
        engine.prepare()
        graphIsReady = true
        return true
    }

    /// CoreAudio's default-output property, read without touching the engine. An unknown device
    /// means the Mac has no output at all — headphones unplugged, or a session with no device.
    private static func hasOutputDevice() -> Bool {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != kAudioObjectUnknown && deviceID != kAudioDeviceUnknown
    }

    /// Builds the graph, starts the engine and puts every voice in play position. `false` means
    /// there is nothing to play into, which is not the ping's fault.
    @discardableResult
    func startIfNeeded() -> Bool {
        if started { return true }
        guard buildGraph() else { return false }
        do {
            try engine.start()
            started = true
            for node in nodes { node.play() }
            Log.audio.info("Audio engine started")
            return true
        } catch {
            isAvailable = false
            Log.audio.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Decodes every sound and texture once, off the main thread, after launch.
    func warmUp() {
        Task.detached(priority: .utility) {
            await AssetCatalog.shared.preloadAll()
        }
    }

    // MARK: - Playback

    /// Plays a sound at `level` (0…1) of the master volume. Returns false when nothing was free.
    @discardableResult
    func play(soundName: String, level: Double = 1) -> Bool {
        guard level > 0, masterVolume > 0 else { return false }
        guard startIfNeeded(), let format = graphFormat else { return false }
        guard let source = AssetCatalog.shared.buffer(for: soundName) else { return false }
        guard let buffer = ready(soundName: soundName, from: source, in: format) else { return false }
        guard let index = busy.firstIndex(of: false) else {
            Log.audio.debug("All \(Self.voicePoolSize) voices busy; skipped \(soundName, privacy: .public)")
            return false
        }
        let node = nodes[index]
        node.volume = masterVolume * Float(max(0, min(level, 1)))
        busy[index] = true
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in self?.settle(index) }
        }
        return true
    }

    @discardableResult
    func play(_ definition: PingDefinition, level: Double = 1) -> Bool {
        play(soundName: definition.sound, level: level)
    }

    @discardableResult
    func playEmote(_ definition: EmoteDefinition, level: Double = 1) -> Bool {
        guard level > 0, masterVolume > 0 else { return false }
        guard startIfNeeded(), let format = graphFormat else { return false }
        guard let source = AssetCatalog.shared.emoteBuffer(named: definition.soundName) else { return false }
        guard let buffer = ready(soundName: "emote:\(definition.soundName)", from: source, in: format) else { return false }
        guard let index = busy.firstIndex(of: false) else {
            Log.audio.debug("All \(Self.voicePoolSize) voices busy; skipped emote \(definition.soundName, privacy: .public)")
            return false
        }
        let node = nodes[index]
        node.volume = masterVolume * Float(max(0, min(level, 1)))
        busy[index] = true
        node.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in self?.settle(index) }
        }
        return true
    }

    /// The wheel's tick, mixed lower than a ping, exactly as the reference does it.
    func playTick(settings: AppSettings) {
        guard settings.tickSoundEnabled else { return }
        _ = play(soundName: PingDefinition.tickSound, level: settings.tickVolume)
    }

    /// `AVAudioPlayerNode` takes a buffer only when its format is exactly the one the voice was
    /// connected with, so anything decoded at another rate or channel count is resampled once
    /// and kept. Without this, a 44.1 kHz game sound on a 48 kHz output throws in AVFAudio.
    private func ready(soundName: String, from buffer: AVAudioPCMBuffer, in format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if let cached = readyBuffers[soundName] { return cached }
        if AudioEngine.isSame(buffer.format, as: format) {
            readyBuffers[soundName] = buffer
            return buffer
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            Log.audio.error("Could not build a resampler for \(soundName, privacy: .public)")
            return nil
        }
        let ratio = format.sampleRate / max(1, buffer.format.sampleRate)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, conversionError == nil else {
            Log.audio.error("Resampling \(soundName, privacy: .public) failed")
            return nil
        }
        readyBuffers[soundName] = output
        return output
    }

    private static func isSame(_ a: AVAudioFormat, as b: AVAudioFormat) -> Bool {
        a.sampleRate == b.sampleRate && a.channelCount == b.channelCount
            && a.commonFormat == b.commonFormat && a.isInterleaved == b.isInterleaved
    }

    private func settle(_ index: Int) {
        guard busy.indices.contains(index) else { return }
        busy[index] = false
    }

    /// Frees every voice at once, e.g. after the engine was stopped or the app disabled.
    func stopAll() {
        for node in nodes {
            node.stop()
            if started { node.play() }
        }
        for index in busy.indices { busy[index] = false }
    }

    /// True when the sound exists on disk, so the settings can grey a row out instead of
    /// silently playing nothing.
    func canPlay(_ soundName: String) -> Bool {
        AssetCatalog.shared.buffer(for: soundName) != nil
    }
}
