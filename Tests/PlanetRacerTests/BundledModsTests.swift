import XCTest
import PlanetRacerCore
@testable import PlanetRacer

final class BundledModsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        setenv("PLANETRACER_ROOT", root.path, 1)
        setenv("PLANETRACER_USER_DIR", root.appendingPathComponent(".build/test-user").path, 1)
    }

    func testMissingPackKeepsOriginalCoreAndShowsError() {
        let model = makeModel()
        let original = model.game
        let choices = model.choices
        model.go(.mods)
        model.openMod(.moonshot, root: Paths.resourceRoot.appendingPathComponent("missing-test-pack"))
        XCTAssertEqual(model.game, original)
        XCTAssertEqual(model.choices, choices)
        XCTAssertEqual(model.screen, .mods)
        XCTAssertTrue(model.titleNote.contains("COULD NOT BE LOADED"))
    }

    func testSavingWhileModdedPreservesBaseQuickRaceSelection() {
        let model = makeModel()
        let original = model.choices
        model.openMod(.bigWheels)
        XCTAssertNotEqual(model.choices, original)
        model.save()
        XCTAssertEqual(Settings.load().race, original)
        model.go(.title)
        XCTAssertEqual(model.choices, original)
    }

    func makeModel() -> GameModel {
        let model = GameModel()
        model.settings = Settings()
        model.game = pr_create(Paths.resourceRoot.appendingPathComponent("data").path)
        XCTAssertEqual(String(cString: pr_error(model.game!)), "")
        return model
    }

    func testTitleOffersBundledMods() {
        let model = makeModel()
        XCTAssertNotNil(model.titleEntries.first { $0.0 == "MODS" })
    }

    func testModSelectionRestoresOriginalCoreAndCareerOnReturn() throws {
        let model = makeModel()
        let original = model.game!
        let choices = model.choices
        pr_career_new(original, "Isolation test", 1)
        let career = String(cString: pr_career_to_json(original))
        let open = try XCTUnwrap(model.titleEntries.first { $0.0 == "MODS" })
        open.1()
        XCTAssertEqual(String(describing: model.screen), "mods")
        let context = try XCTUnwrap(model.menuContext)
        model.activate(context, 2) // Big Wheels
        XCTAssertEqual(model.screen, .quickRace)
        XCTAssertNotEqual(model.game, original)
        XCTAssertEqual(model.choices.planet, 5)
        XCTAssertEqual(model.choices.engine, 1)
        XCTAssertEqual(model.choices.tires, 2)
        pr_race_begin(model.game!, PRRaceConfig(planet: 5, opponent: 0, engine: 1, tires: 2, chassis: 1, afterburner: 2, color: 1, difficulty: 0))
        var frame = PRFrame()
        pr_race_frame(model.game!, &frame)
        let wheels = cArray(frame.car, PRPoint.self, count: Int(frame.pointCount)).filter { $0.wheel }
        XCTAssertEqual(wheels.map { $0.r }, [35, 26])
        model.go(.title)
        XCTAssertEqual(model.game, original)
        XCTAssertEqual(model.choices, choices)
        XCTAssertEqual(String(cString: pr_career_to_json(original)), career)
    }

    func testEachModLoadsAndBackRestoresOriginal() throws {
        let model = makeModel()
        let original = model.game!
        for name in ["Moonshot", "Jelly Racer", "Big Wheels"] {
            try XCTUnwrap(model.titleEntries.first { $0.0 == "MODS" }).1()
            let context = try XCTUnwrap(model.menuContext)
            let row = try XCTUnwrap(model.items(context).first { $0.label == name.uppercased() })
            model.activate(context, row.id)
            XCTAssertEqual(model.screen, .quickRace)
            XCTAssertEqual(String(cString: model.planet(5).name), name)
            model.back(.quickRace)
            XCTAssertEqual(model.game, original)
            XCTAssertEqual(String(cString: model.planet(5).name), "Sample Handmade Track")
        }
    }
}
