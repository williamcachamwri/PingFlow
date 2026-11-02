import XCTest
@testable import PingFlowKit

/// The catalogue is the contract between the extracted Riot assets and everything that draws or
/// plays them. A ping whose texture or sound name is wrong is a ping that silently does nothing.
final class PingDefinitionTests: XCTestCase {

    func testTheDefaultWheelIsTheLeagueArrangement() {
        XCTAssertEqual(PingDefinition.defaultWheel,
                       [.danger, .push, .onMyWay, .allIn, .assist, .needVision, .enemyMissing, .enemyVision])
        XCTAssertEqual(PingDefinition.defaultWheel.map { PingDefinition.definition(for: $0).name },
                       ["Danger", "Push", "On My Way", "All In", "Assist Me", "Need Vision",
                        "Enemy Missing", "Enemy Vision"])
        XCTAssertEqual(PingDefinition.defaultWheel.count, PingDefinition.wheelSlotCount)
    }

    func testEveryIdentifierResolvesToADefinition() {
        for id in PingDefinition.ID.allCases {
            XCTAssertNotNil(PingDefinition.allByID[id], "\(id.rawValue) has no definition")
            XCTAssertEqual(PingDefinition.definition(for: id).id, id)
        }
        XCTAssertEqual(Set(PingDefinition.all.map { $0.id }).count, PingDefinition.all.count,
                       "the catalogue must not list a ping twice")
        XCTAssertEqual(PingDefinition.all.count, PingDefinition.ID.allCases.count)
    }

    func testEveryPingHasArtAndSound() {
        for ping in PingDefinition.all {
            XCTAssertFalse(ping.iconTexture.isEmpty, "\(ping.name) has no wheel texture")
            XCTAssertFalse(ping.artTextures.isEmpty, "\(ping.name) has no ping art")
            XCTAssertFalse(ping.sound.isEmpty, "\(ping.name) has no sound")
            XCTAssertFalse(ping.usage.isEmpty, "\(ping.name) has no description")
            XCTAssertTrue(ping.colorHex.hasPrefix("#"), "\(ping.name) colour is not a hex")
            XCTAssertEqual(ping.colorHex.count, 7, "\(ping.name) colour is not #rrggbb")
        }
    }

    func testAllInIsTheTwoArtVariant() {
        XCTAssertTrue(PingDefinition.definition(for: .allIn).isAllIn)
        XCTAssertFalse(PingDefinition.definition(for: .danger).isAllIn)
    }

    /// Identifiers are written to the settings file, so renaming one silently loses someone's wheel.
    func testRawIdentifiersMatchTheExtractedAssetNames() {
        XCTAssertEqual(PingDefinition.ID.onMyWay.rawValue, "omw")
        XCTAssertEqual(PingDefinition.ID.enemyMissing.rawValue, "missing")
        XCTAssertEqual(PingDefinition.ID.enemyVision.rawValue, "enemyvision")
        XCTAssertEqual(PingDefinition.ID.visionCleared.rawValue, "visioncleared")
        XCTAssertEqual(PingDefinition.ID.upsideDownMissing.rawValue, "missingflip")
        XCTAssertEqual(PingDefinition.ID.allIn.rawValue, "allin")
        XCTAssertEqual(PingDefinition.ID.needVision.rawValue, "needvision")
    }

    func testCatalogueDirectoryLayout() throws {
        let root = try XCTUnwrap(AssetCatalog.shared.rootDirectory,
                                 "the asset folder must be found next to the binary or in the repository")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("textures").path),
                      "expected \(root.path)/textures")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sounds").path),
                      "expected \(root.path)/sounds")
    }

    /// Missing art must degrade to the fallback, never to a blank slice.
    func testInventoryAccountsForEveryFileTheCatalogueWants() {
        let inventory = AssetCatalog.shared.inventory()
        XCTAssertFalse(inventory.isEmpty)
        let wanted = Set(PingDefinition.all.flatMap { [$0.iconTexture] + $0.artTextures })
        let presentTextures = inventory.filter { $0.kind == .texture && $0.present }.map(\.name)
        for name in wanted {
            XCTAssertTrue(presentTextures.contains(name), "\(name) is listed but not on disk")
        }
        let sounds = inventory.filter { $0.kind == .sound && $0.present }.map(\.name)
        for name in PingDefinition.all.map(\.sound) {
            XCTAssertTrue(sounds.contains(name), "\(name) is listed but not on disk")
        }
        XCTAssertTrue(AssetCatalog.shared.hasEveryAsset,
                      "the shipped catalogue should be complete; a missing file is a real defect")
    }

    func testAttributionTravelsWithTheAssets() throws {
        let root = try XCTUnwrap(AssetCatalog.shared.rootDirectory)
        let url = root.appendingPathComponent("ATTRIBUTION.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Riot's assets ship with their licence note or not at all")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("riot"), "the note must name the owner")
    }
}
