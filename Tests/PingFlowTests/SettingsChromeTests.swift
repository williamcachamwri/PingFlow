import XCTest
@testable import PingFlowKit

/// The settings window's own behaviour: what the category menu narrows, what the search field can
/// find, and what a file written by an older build still means now that three settings are gone.
@MainActor
final class SettingsChromeTests: XCTestCase {

    private var directory: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PingFlowChrome-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Pruned settings

    /// `launchAtLogin`, `language` and `fullscreenCompatibility` were dropped because nothing in the
    /// app acted on them. A file that still carries them has to load, not be treated as corrupt.
    func testAFileFromAnOlderBuildStillLoads() throws {
        let json = """
        { "isEnabled": false, "launchAtLogin": true, "language": "vietnamese",
          "fullscreenCompatibility": false, "wheelSize": 520, "volume": 0.4 }
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("settings-test.json"))
        let store = SettingsStore(in: directory)
        XCTAssertNil(store.fileIssue)
        XCTAssertFalse(store.settings.isEnabled)
        XCTAssertEqual(store.settings.wheelSize, 520, accuracy: 0.001)
        XCTAssertEqual(store.settings.volume, 0.4, accuracy: 0.001)
    }

    // MARK: - The hub

    func testTheChosenCentrePingIsWhatTheWheelDraws() {
        let scene = WheelScene()
        var settings = AppSettings()
        settings.clickPing = .bait
        scene.sync(settings: settings.normalized())
        XCTAssertEqual(scene.hubImageName, PingDefinition.definition(for: .bait).iconTexture)
        XCTAssertNotEqual(scene.hubImageName, PingDefinition.logoTexture)
    }

    // MARK: - Categories

    func testEveryPingBelongsToExactlyOneCategory() {
        for definition in PingDefinition.all {
            XCTAssertTrue(PingCategory.allCases.contains(definition.category))
        }
        for category in PingCategory.allCases {
            XCTAssertFalse(PingDefinition.all.filter { $0.category == category }.isEmpty,
                           "\(category.rawValue) is offered as a filter but holds nothing")
        }
    }

    func testScopeNarrowsToTheCategoryAlone() {
        let vision = PingDefinition.all.filter { $0.category == .vision }
        XCTAssertFalse(vision.isEmpty)
        XCTAssertEqual(PingDefinition.all.filter { Scope.category(.vision).contains($0) }.count, vision.count)
        XCTAssertEqual(PingDefinition.all.filter { Scope.all.contains($0) }.count, PingDefinition.all.count)
    }

    // MARK: - Search

    func testCatalogIdsAreUnique() {
        let ids = SettingsCatalog.hits.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "a duplicated id makes a highlight ambiguous")
    }

    func testEverySettingTheWindowShowsCanBeFound() {
        // The row ids the panes highlight, written down here so a renamed setting fails loudly.
        let expected = ["isEnabled", "launchAtLogin", "showMenuBarIcon", "showDockIconWhileSettingsOpen",
                        "activationKey", "secondaryActivationKey", "dragThreshold", "toggleShortcut",
                        "clickBehaviour", "cancelOnRightClick", "cancelOnOtherKeyPress",
                        "wheelSize", "overlayOpacity", "pingSize", "pingDuration", "animationIntensity",
                        "previewPing", "preview", "permissions", "about", "reset"]
        let known = Set(SettingsCatalog.hits.map(\.id))
        for id in expected {
            XCTAssertTrue(known.contains(id), "\(id) is highlighted by a row but is not searchable")
        }
    }

    func testSearchMatchesOnAliasWordsNotOnlyTitles() {
        let found = SettingsCatalog.results(query: "hotkey", scope: .all)
        XCTAssertTrue(found.contains { $0.id == "toggleShortcut" })
        XCTAssertTrue(SettingsCatalog.results(query: "ward", scope: .all)
                        .contains { $0.destination == .ping(.needVision) })
        XCTAssertTrue(SettingsCatalog.results(query: "nothing at all like this", scope: .all).isEmpty)
    }

    func testCategoryScopeHidesSettingsThatAreNotPings() {
        let found = SettingsCatalog.results(query: "ping", scope: .category(.vision))
        XCTAssertTrue(found.allSatisfy { $0.ping != nil })
    }

    // MARK: - History

    func testBackAndForwardWalkTheRealPages() {
        let router = SettingsRouter()
        router.go(.pane(.sounds))
        router.go(.ping(.danger))
        XCTAssertEqual(router.destination, .ping(.danger))
        XCTAssertTrue(router.canGoBack)
        XCTAssertEqual(router.owningPane, .pingWheel, "a ping is reached from the wheel page")
        router.back()
        XCTAssertEqual(router.destination, .pane(.sounds))
        router.back()
        XCTAssertEqual(router.destination, .pane(.general))
        XCTAssertFalse(router.canGoBack)
        router.forward()
        XCTAssertEqual(router.destination, .pane(.sounds))
        XCTAssertEqual(router.owningPane, .sounds)
    }

    func testGoingBackAndForwardTwiceDoesNotGrowTheHistory() {
        let router = SettingsRouter()
        router.go(.pane(.about))
        router.back()
        router.forward()
        router.forward()
        XCTAssertEqual(router.destination, .pane(.about))
        XCTAssertFalse(router.canGoForward)
    }

    func testSearchingClearsWhenAPageOpens() {
        let router = SettingsRouter()
        router.query = "vol"
        router.go(.pane(.sounds))
        XCTAssertEqual(router.query, "")
    }
}
