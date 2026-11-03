import AppKit
import Combine
import Foundation

/// One file from Finder, one emote. Imports run off the main thread and report back through
/// `pending` and `notice`, so a drop of thirty gifs never blocks the wheel editor.
@MainActor
final class EmoteImportQueue: ObservableObject {
    struct Pending: Identifiable, Equatable {
        let id: String
        let name: String
        let sourcePath: String
    }

    struct Notice: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var pending: [Pending] = []
    @Published private(set) var notice: Notice?

    private let library: EmoteLibrary

    init(library: EmoteLibrary) {
        self.library = library
    }

    func clearNotice() { notice = nil }

    /// What one file became: a finished emote, a name it already belongs to, or a reason.
    fileprivate enum Outcome {
        case added(CustomEmote)
        case duplicate(String)
        case failed(String)
    }

    private struct Plan {
        let url: URL
        let id: String
        let folder: URL
    }

    // MARK: - Adding

    /// Drops of art files: one emote per file, in the order they were dropped.
    func add(artURLs: [URL]) {
        let queued = artURLs.filter { url in !pending.contains { $0.sourcePath == url.path } }
        guard !queued.isEmpty else { return }
        // The folder's name is the emote's id, so the library can always find what the import wrote.
        let plans = queued.map { url in
            let token = UUID().uuidString
            return Plan(url: url, id: token, folder: library.folder(for: token))
        }
        for plan in plans {
            begin(id: plan.id, name: EmoteImporter.suggestedName(for: plan.url), sourcePath: plan.url.path)
        }
        let capacityLeft = EmoteImporter.libraryCapacity - library.imported.count
        let taken = Dictionary(uniqueKeysWithValues: library.imported.map { ($0.media.contentHash, $0.name) })

        Task.detached(priority: .userInitiated) { [weak self] in
            // One file at a time: an export already uses every core it can get, and a drop of
            // thirty clips decoding at once would only make each of them slower.
            var results: [Outcome] = []
            for (offset, plan) in plans.enumerated() {
                results.append(await Self.importArt(plan,
                                                    capacityLeft: capacityLeft - offset,
                                                    taken: taken,
                                                    name: EmoteImporter.suggestedName(for: plan.url)))
            }
            await self?.finishAdd(plans: plans, results: results)
        }
    }

    /// The main-actor half of an add: the library takes the emote, the card reports what happened.
    @MainActor
    private func finishAdd(plans: [Plan], results: [Outcome]) {
        for (plan, result) in zip(plans, results) {
            finish(id: plan.id)
            switch result {
            case .added(let emote):
                library.add(emote)
                report(.init(text: "\(emote.name) added — \(emote.media.kindLabel).", isError: false))
            case .duplicate(let name):
                report(.init(text: "Already in the library as \(name).", isError: true))
            case .failed(let message):
                report(.init(text: message, isError: true))
            }
        }
    }

    /// Runs the heavy work for one plan. Nothing in here touches the library, so it can run on
    /// any thread.
    private nonisolated static func importArt(_ plan: Plan, capacityLeft: Int,
                                             taken: [String: String], name: String) async -> Outcome {
        guard capacityLeft > 0 else {
            return .failed(EmoteImportError.fullLibrary(limit: EmoteImporter.libraryCapacity).message)
        }
        do {
            let media = try await EmoteImporter.makeMedia(from: plan.url, into: plan.folder)
            if let existing = taken[media.contentHash] {
                try? FileManager.default.removeItem(at: plan.folder)
                return .duplicate(existing)
            }
            return .added(CustomEmote(id: plan.id,
                                      name: name,
                                      media: media,
                                      sound: nil,
                                      originName: plan.url.lastPathComponent,
                                      createdAt: Date()))
        } catch let error as EmoteImportError {
            try? FileManager.default.removeItem(at: plan.folder)
            return .failed(error.message)
        } catch {
            try? FileManager.default.removeItem(at: plan.folder)
            return .failed("Could not be imported.")
        }
    }

    // MARK: - Replacing

    /// Swaps an import's art for another file, keeping its name, its sound and its wheel slots.
    func replaceArt(of id: String, with url: URL) {
        guard let emote = library.importedEmote(id) else { return }
        begin(id: id, name: emote.name, sourcePath: url.path)
        let folder = library.folder(for: id)
        Task.detached(priority: .userInitiated) { [weak self] in
            Self.clearArt(in: folder)
            let result: Outcome
            do {
                var next = emote
                next.media = try await EmoteImporter.makeMedia(from: url, into: folder)
                result = .added(next)
            } catch let error as EmoteImportError {
                result = .failed(error.message)
            } catch {
                result = .failed("Could not be read.")
            }
            await self?.finishReplacement(id: id, result: result,
                                          fileName: url.lastPathComponent, verb: "shows")
        }
    }

    /// Attaches a sound, or takes it away when there is no file. A video here is refused on
    /// purpose: nothing is converted, because conversion would need a binary the Mac may not have.
    func replaceSound(of id: String, with url: URL?) {
        guard let emote = library.importedEmote(id) else { return }
        guard let url else {
            var next = emote
            next.sound = nil
            Self.clearSound(in: library.folder(for: id))
            library.update(next)
            library.invalidate(id)
            report(.init(text: "\(emote.name) is silent.", isError: false))
            return
        }
        begin(id: id, name: emote.name, sourcePath: url.path)
        let folder = library.folder(for: id)
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Outcome
            do {
                Self.clearSound(in: folder)
                var next = emote
                next.sound = try EmoteImporter.makeSound(from: url, into: folder)
                result = .added(next)
            } catch let error as EmoteImportError {
                result = .failed(error.message)
            } catch {
                result = .failed("Could not be read.")
            }
            await self?.finishReplacement(id: id, result: result,
                                          fileName: url.lastPathComponent, verb: "sounds like")
        }
    }

    /// The main-actor half of a replacement: the emote keeps its id, its slots and its name, so
    /// the wheel needs no repair when its art or its sound changes.
    @MainActor
    private func finishReplacement(id: String, result: Outcome, fileName: String, verb: String) {
        finish(id: id)
        switch result {
        case .added(let next):
            library.update(next)
            library.invalidate(id)
            report(.init(text: "\(next.name) now \(verb) \(fileName).", isError: false))
        case .duplicate(let name):
            report(.init(text: "Already in the library as \(name).", isError: true))
        case .failed(let message):
            report(.init(text: message, isError: true))
        }
    }

    // MARK: - Bookkeeping

    private func begin(id: String, name: String, sourcePath: String) {
        pending.removeAll { $0.id == id }
        pending.append(Pending(id: id, name: name, sourcePath: sourcePath))
    }

    private func finish(id: String) {
        pending.removeAll { $0.id == id }
    }

    private func report(_ note: Notice) {
        notice = note
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.notice == note else { return }
            self.notice = nil
        }
    }

    fileprivate nonisolated static func clearArt(in folder: URL) {
        let finder = FileManager.default
        for name in ["art.png", "art.gif", "art.mp4", "poster.png"] {
            try? finder.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    fileprivate nonisolated static func clearSound(in folder: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix("sound.") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
