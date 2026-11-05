// End-to-end coaching workflows using XCTest and Debug-only fixtures.
// Accessibility identifiers are test contracts; reset orientation/fixtures in each scenario.
// Geometry assertions supplement (but do not replace) physical-device layout checks.

import XCTest

final class PitchHarborUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testAnyPositionAndCustomNames() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let player = app.buttons["teamPlayer-6"]
        scrollTo(player, app: app)
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        let any = app.switches["anyPosition"]
        XCTAssertTrue(any.waitForExistence(timeout: 5))
        any.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(any.value as? String, "1")
        app.buttons["Save"].tap()
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(player.label.contains("Any Position"))
        scrollTo(app.buttons["Edit"], app: app, towardTop: true)
        app.buttons["Edit"].tap()
        app.buttons["Position Names"].tap()
        let name = app.textFields["positionName-CM"]
        scrollTo(name, app: app)
        name.tap()
        name.typeText("Center")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Save"].tap()
        let lineup = app.buttons["teamStartingLineup"]
        scrollTo(lineup, app: app, towardTop: true)
        lineup.tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Center"))
    }
    @MainActor func testBoardDeleteCancelThenConfirm() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Library"].tap()
        let delete = app.buttons["deleteBoard-Build from the Back"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let prompt = app.alerts["Delete This Board?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.buttons["Cancel"].tap()
        XCTAssertTrue(delete.exists)
        delete.tap()
        prompt.buttons["Delete Board"].tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your Playbook Starts Here"].exists)
    }
    @MainActor func testDeleteMatchHistoryWithCancelAndConfirmation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 8))
        app.buttons["Start Match"].tap()
        app.buttons["End Half"].tap()
        app.buttons["confirmEndPeriod"].tap()
        app.buttons["Start Second Half"].tap()
        app.buttons["Full Time"].tap()
        app.buttons["confirmEndPeriod"].tap()
        let options = app.buttons["Match Options"]
        scrollTo(options, app: app, towardTop: true)
        options.tap()
        app.buttons["Delete Match"].tap()
        let prompt = app.alerts["Delete This Match?"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertTrue(
            prompt.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Westside")).firstMatch.exists)
        prompt.buttons["Cancel"].tap()
        options.tap()
        app.buttons["Match History"].tap()
        let delete = app.buttons["deleteHistoryMatch-Westside"]
        scrollTo(delete, app: app)
        XCTAssertTrue(delete.isHittable)
        XCTAssertGreaterThanOrEqual(delete.frame.height, 44)
        delete.tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["openHistoryMatch-Westside"].exists)
        delete.tap()
        app.buttons["confirmDeleteMatch"].tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["openHistoryMatch-Westside"].exists)
        XCTAssertFalse(app.staticTexts["Recent Matches"].exists)
        scrollTo(app.buttons["Set Up a Match"], app: app, towardTop: true)
        XCTAssertTrue(app.buttons["Set Up a Match"].isHittable)
        app.buttons["Teams"].tap()
        XCTAssertTrue(app.buttons["teamStartingLineup"].waitForExistence(timeout: 5))
    }
    @MainActor func testManualLineupSaveAndReopen() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let teamLineup = app.buttons["teamStartingLineup"]
        XCTAssertTrue(teamLineup.waitForExistence(timeout: 8))
        teamLineup.tap()
        let field = app.otherElements["lineupField"], save = app.buttons["saveLineup"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Build a partial custom template directly, without asking Auto Pick for a lineup.
        app.buttons["lineupBench-1"].tap()
        field.buttons["pitchSlot-5"].tap()
        app.buttons["lineupBench-2"].tap()
        field.buttons["pitchSlot-0"].tap()
        XCTAssertTrue(field.buttons["pitchSlot-0"].label.contains("Jordan"))
        XCTAssertTrue(field.buttons["pitchSlot-5"].label.contains("Avery"))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(teamLineup.waitForExistence(timeout: 5))
        teamLineup.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.buttons["pitchSlot-0"].label.contains("Jordan"))
        XCTAssertTrue(field.buttons["pitchSlot-5"].label.contains("Avery"))
        XCTAssertEqual(app.staticTexts["lineupCount"].label, "2/11 Starters")
        app.buttons["Cancel"].firstMatch.tap()
        // A separate ready-match fixture verifies the same Save action before kickoff.
        app.terminate()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat"]
        app.launch()
        let edit = app.buttons["Edit Starting Lineup"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.buttons["pitchSlot-0"].tap()
        field.buttons["pitchSlot-5"].tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Harper"))
        XCTAssertFalse(app.alerts["Use Unapproved Positions?"].exists)
        edit.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.buttons["pitchSlot-0"].label.contains("Harper"))
        XCTAssertTrue(field.buttons["pitchSlot-5"].label.contains("Avery"))
    }
    @MainActor func testCustomTeamPositionsSaveAndRemainMatchDefaults() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let teamLineup = app.buttons["teamStartingLineup"]
        XCTAssertTrue(teamLineup.waitForExistence(timeout: 8))
        teamLineup.tap()
        XCTAssertTrue(app.staticTexts["lineupCount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lineupCount"].label, "0/11 Starters")
        app.buttons["autoPickLineup"].tap()
        app.buttons["pitchSlot-0"].tap()
        app.buttons["pitchSlot-5"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Harper"))
        let save = app.buttons["saveLineup"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(teamLineup.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Use Unapproved Positions?"].exists)
        teamLineup.tap()
        XCTAssertTrue(app.buttons["pitchSlot-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Harper"))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Avery"))
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Match Day"].tap()
        app.buttons["Set Up a Match"].tap()
        let opponent = app.textFields["opponentField"]
        XCTAssertTrue(opponent.waitForExistence(timeout: 5))

        opponent.tap()
        opponent.typeText("Visitors\n")
        let rules = app.switches["I’ve Checked These Match Settings"]
        scrollTo(rules, app: app)
        rules.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(rules.value as? String, "1")
        let edit = app.buttons["editStartingLineup"]
        scrollTo(edit, app: app)
        edit.tap()
        XCTAssertTrue(app.buttons["pitchSlot-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Harper"))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Avery"))
        save.tap()
        let create = app.buttons["createMatch"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))

        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Harper"))
        app.buttons["Edit Starting Lineup"].firstMatch.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let editorField = app.otherElements["lineupField"]
        editorField.buttons["pitchSlot-0"].tap()
        editorField.buttons["pitchSlot-9"].tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Skyler"))
        XCTAssertFalse(app.alerts["Use Unapproved Positions?"].exists)
        // Direct pre-kickoff swaps are customizable too, without position approval dialogs.
        app.buttons["pitchSlot-0"].tap()
        app.buttons["pitchSlot-9"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Harper"))
        XCTAssertFalse(app.alerts["Use Unapproved Positions?"].exists)
    }
    @MainActor func testReturnToMatchBannerFromEveryTab() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 8))
        app.buttons["Start Match"].tap()
        app.buttons["Goal For"].tap()
        for tab in ["Teams", "Practice", "Library"] {
            app.buttons[tab].tap()
            let banner = app.buttons["returnToMatchBanner"]
            XCTAssertTrue(banner.waitForExistence(timeout: 5))
            XCTAssertTrue(banner.isHittable)
            XCTAssertGreaterThanOrEqual(banner.frame.height, 43.99)
            banner.tap()
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
            XCTAssertFalse(banner.exists)
            XCTAssertTrue(app.buttons["Undo"].isEnabled)
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons["Teams"].tap()
        let banner = app.buttons["returnToMatchBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.isHittable)
        banner.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        app.buttons["Pause"].tap()
        app.buttons["Match Options"].tap()
        app.buttons["Match History"].tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        XCTAssertFalse(banner.exists)
    }
    @MainActor func testSavedTeamLineupAndQuickAttendance() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let template = app.buttons["teamStartingLineup"]
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        app.buttons["autoPickLineup"].tap()
        let reserve = app.buttons["lineupBench-12"]
        XCTAssertTrue(reserve.waitForExistence(timeout: 5))
        reserve.tap()
        app.buttons["pitchSlot-5"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Finley"))
        app.buttons["saveLineup"].tap()
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Finley"))
        app.buttons["Cancel"].firstMatch.tap()
        let available = app.switches["teamAvailability-12"]
        scrollTo(available, app: app)
        available.tap()
        XCTAssertEqual(available.value as? String, "0")
        app.buttons["Match Day"].tap()
        app.buttons["Set Up a Match"].tap()
        let opponent = app.textFields["opponentField"]
        XCTAssertTrue(opponent.waitForExistence(timeout: 5))

        opponent.tap()
        opponent.typeText("Visitors\n")
        let edit = app.buttons["editStartingLineup"]
        scrollTo(edit, app: app)
        edit.tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pitchSlot-5"].label.contains("Finley"))
        XCTAssertFalse(app.buttons["lineupBench-12"].exists)
        app.buttons["Cancel"].firstMatch.tap()
        let attending = app.switches["matchAttendance-12"]
        scrollTo(attending, app: app)
        attending.tap()
        XCTAssertEqual(attending.value as? String, "1")
        scrollTo(edit, app: app, towardTop: true)
        edit.tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Finley"))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())

        shot.name = "Saved Team Starters Restored After Attendance"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["saveLineup"].tap()
        let rules = app.switches["I’ve Checked These Match Settings"]
        scrollTo(rules, app: app, towardTop: true)
        if rules.value as? String != "1" { rules.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        XCTAssertEqual(rules.value as? String, "1")
        let create = app.buttons["createMatch"]
        if !create.isEnabled { print(app.debugDescription) }
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Finley"))
        app.buttons["Teams"].tap()
        scrollTo(available, app: app)
        XCTAssertEqual(available.value as? String, "0")
        scrollTo(template, app: app, towardTop: true)
        template.tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Finley"))
    }
    @MainActor func testMidfieldSetupEditsReadyMatchAndPreservesCancel() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat", "--preview-full-match"]
        app.launch()
        let edit = app.buttons["Edit Starting Lineup"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        let midfield = app.buttons["midfieldSetupPicker"]
        XCTAssertTrue(midfield.waitForExistence(timeout: 5))
        midfield.tap()
        app.buttons["Wide · LM / CM / RM"].tap()
        let field = app.otherElements["lineupField"]
        XCTAssertTrue(field.buttons["pitchSlot-5"].label.contains(", LM,"))
        XCTAssertTrue(field.buttons["pitchSlot-7"].label.contains(", RM,"))
        XCTAssertTrue(field.buttons["pitchSlot-8"].label.contains(", LW,"))
        app.buttons["saveLineup"].tap()
        XCTAssertFalse(app.alerts["Use Unapproved Positions?"].exists)
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains(", LM,"))
        edit.tap()
        XCTAssertTrue(midfield.waitForExistence(timeout: 5))
        midfield.tap()
        app.buttons["Two Attacking Mids · AM / DM / AM"].tap()
        XCTAssertTrue(field.buttons["pitchSlot-5"].label.contains(", AM,"))
        XCTAssertTrue(field.buttons["pitchSlot-6"].label.contains(", DM,"))
        XCTAssertGreaterThan(field.buttons["pitchSlot-6"].frame.midY, field.buttons["pitchSlot-5"].frame.midY)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Formation-Aware Midfield"

        shot.lifetime = .keepAlways
        add(shot)
        XCUIDevice.shared.orientation = .landscapeLeft
        let slots = field.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pitchSlot-'"))
        XCTAssertEqual(slots.count, 11)
        for i in 0..<slots.count {
            XCTAssertTrue(slots.element(boundBy: i).isHittable)
            let frame = slots.element(boundBy: i).frame
            XCTAssertGreaterThanOrEqual(frame.minX, field.frame.minX - 1)
            XCTAssertGreaterThanOrEqual(frame.minY, field.frame.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxX, field.frame.maxX + 1)
            XCTAssertLessThanOrEqual(frame.maxY, field.frame.maxY + 1)
            for j in (i + 1)..<slots.count {
                let overlap = frame.intersection(slots.element(boundBy: j).frame)
                XCTAssertTrue(
                    overlap.isNull || overlap.width < 1 || overlap.height < 1,
                    "\(slots.element(boundBy:i).label) overlaps \(slots.element(boundBy:j).label): \(overlap)")
            }
        }
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains(", LM,"))
        edit.tap()
        XCTAssertTrue(midfield.waitForExistence(timeout: 5))
        XCTAssertTrue(midfield.value as? String == "Wide · LM / CM / RM")
    }
    @MainActor func testWideMidfieldPlayerPositionsSave() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let player = app.buttons["teamPlayer-6"]
        scrollTo(player, app: app)
        player.tap()
        for role in ["LM", "RM"] {
            let choice = app.buttons["alsoPlays-\(role)"]
            scrollTo(choice, app: app)
            choice.tap()
            XCTAssertEqual(choice.value as? String, "Selected")
        }
        app.buttons["Save"].tap()
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        scrollTo(player, app: app)
        XCTAssertTrue(player.label.contains("LM") && player.label.contains("RM"))
        player.tap()
        for role in ["LM", "RM"] {
            let choice = app.buttons["alsoPlays-\(role)"]
            scrollTo(choice, app: app)
            XCTAssertEqual(choice.value as? String, "Selected")
        }
    }
    @MainActor func testQuickLiveFieldSubstitution() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat", "--preview-full-match"]
        app.launch()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 8))
        app.buttons["matchBench-12"].tap()
        app.buttons["pitchSlot-5"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Finley"))
        XCTAssertFalse(app.buttons["saveLineup"].exists)
        app.buttons["pitchSlot-5"].tap()
        app.buttons["matchBench-6"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Harper"))
        app.buttons["Start Match"].tap()
        let midfielder = app.buttons["pitchSlot-5"]
        XCTAssertTrue(midfielder.label.contains("Harper"))
        midfielder.tap()
        XCTAssertEqual(midfielder.value as? String, "Selected")
        XCTAssertFalse(app.buttons["Confirm Players Are on the Field"].exists)
        midfielder.tap()
        XCTAssertNotEqual(midfielder.value as? String, "Selected")
        let incoming = app.buttons["matchBench-12"]
        incoming.tap()
        XCTAssertEqual(incoming.value as? String, "Selected")
        midfielder.tap()
        XCTAssertFalse(app.buttons["Confirm Players Are on the Field"].exists)
        XCTAssertTrue(midfielder.waitForExistence(timeout: 5))
        XCTAssertTrue(midfielder.label.contains("Finley"))
        XCTAssertTrue(app.buttons["Pause"].exists)
        app.buttons["Undo"].tap()
        XCTAssertTrue(midfielder.label.contains("Harper"))
        midfielder.tap()
        app.buttons["pitchSlot-6"].tap()
        XCTAssertTrue(app.alerts["Confirm Position Change"].waitForExistence(timeout: 5))
        app.alerts.buttons["Confirm Change"].tap()
        XCTAssertTrue(app.alerts["Confirm Position Change"].waitForNonExistence(timeout: 3))
        let swapped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'Harper'"), object: app.buttons["pitchSlot-6"])
        XCTAssertEqual(XCTWaiter.wait(for: [swapped], timeout: 3), .completed)
        app.buttons["pitchSlot-6"].tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Quick Live Field Selection"

        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Pause"].tap()
        XCTAssertNotEqual(app.buttons["pitchSlot-6"].value as? String, "Selected")
    }
    @MainActor func testPracticeTapMoveSwapAndUndo() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-board", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["showPlayers"].waitForExistence(timeout: 8))
        app.buttons["showPlayers"].tap()
        let field = app.otherElements["teachingField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let marker = app.buttons.matching(NSPredicate(format: "label == 'Player 1'")).firstMatch
        let second = app.buttons.matching(NSPredicate(format: "label == 'Player 2'")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        let origin = marker.frame
        marker.tap()
        XCTAssertEqual(marker.value as? String, "Selected")
        marker.tap()
        XCTAssertNotEqual(marker.value as? String, "Selected")
        marker.tap()
        let destination = field.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45))
        destination.tap()
        XCTAssertLessThan(marker.frame.midX, field.frame.minX + field.frame.width * 0.2)
        XCTAssertNotEqual(marker.value as? String, "Selected")
        app.buttons["Undo"].tap()
        XCTAssertEqual(marker.frame.midX, origin.midX, accuracy: 2)

        XCTAssertEqual(marker.frame.midY, origin.midY, accuracy: 2)
        app.buttons["Redo"].tap()
        let moved = marker.frame, other = second.frame
        marker.tap()
        second.tap()
        XCTAssertEqual(marker.frame.midX, other.midX, accuracy: 2)

        XCTAssertEqual(marker.frame.midY, other.midY, accuracy: 2)
        XCTAssertEqual(second.frame.midX, moved.midX, accuracy: 2)
        app.buttons["Undo"].tap()
        XCTAssertEqual(marker.frame.midX, moved.midX, accuracy: 2)
        marker.tap()
        app.buttons["Draw"].tap()
        XCTAssertNotEqual(marker.value as? String, "Selected")
        app.buttons["Add"].tap()
        app.buttons["Cone"].tap()
        let cone = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cone'")).firstMatch
        XCTAssertTrue(cone.waitForExistence(timeout: 5))
        XCTAssertEqual(cone.value as? String, "Selected")
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55)).tap()
        XCTAssertGreaterThan(cone.frame.midX, field.frame.minX + field.frame.width * 0.75)
        marker.tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Practice Tap to Move"

        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["exitTeaching"].tap()
        app.buttons["Done"].tap()
    }
    @MainActor func testLineupDragSwapTapAndLiveSubstitution() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat", "--preview-full-match"]
        app.launch()
        let edit = app.buttons["Edit Starting Lineup"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        let bench = app.buttons["lineupBench-12"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        let center = app.otherElements["lineupField"].buttons["pitchSlot-5"]
        bench.press(forDuration: 0.8, thenDragTo: center)
        XCTAssertTrue(center.label.contains("Finley"))
        center.press(forDuration: 0.8, thenDragTo: app.otherElements["lineupField"].buttons["pitchSlot-6"])
        XCTAssertTrue(app.otherElements["lineupField"].buttons["pitchSlot-6"].label.contains("Finley"))
        app.otherElements["lineupField"].buttons["pitchSlot-9"].tap()
        XCTAssertEqual(app.otherElements["lineupField"].buttons["pitchSlot-9"].value as? String, "Selected")
        let replacement = app.buttons["lineupBench-14"]
        scrollTo(replacement, app: app)
        replacement.tap()
        XCTAssertTrue(app.otherElements["lineupField"].buttons["pitchSlot-9"].label.contains("Rowan"))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())

        screenshot.name = "Editable Starting Lineup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["saveLineup"].tap()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-6"].label.contains("Finley"))
        app.buttons["Start Match"].tap()
        let incoming = app.buttons["matchBench-6"]
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        incoming.press(forDuration: 0.8, thenDragTo: app.buttons["pitchSlot-5"])
        XCTAssertFalse(app.buttons["Confirm Players Are on the Field"].exists)
        XCTAssertTrue(app.buttons["pitchSlot-5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Harper"))
        app.buttons["pitchSlot-5"].press(forDuration: 0.8, thenDragTo: app.buttons["pitchSlot-6"])
        XCTAssertTrue(app.alerts["Confirm Position Change"].waitForExistence(timeout: 5))
        app.alerts.buttons["Confirm Change"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-6"].label.contains("Harper"))
        XCTAssertTrue(app.buttons["Pause"].exists)
    }
    @MainActor func testSetupLineupTapSelectionAndCancel() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Set Up a Match"].tap()
        let edit = app.buttons["editStartingLineup"]
        scrollTo(edit, app: app)
        edit.tap()
        let keeper = app.buttons["pitchSlot-0"]
        XCTAssertTrue(keeper.waitForExistence(timeout: 5))
        XCTAssertTrue(keeper.label.contains("Avery"))
        keeper.tap()
        XCTAssertEqual(keeper.value as? String, "Selected")
        XCTAssertFalse(app.buttons["lineupChoice-1"].exists)
        keeper.tap()
        XCTAssertNotEqual(keeper.value as? String, "Selected")
        let bench = app.buttons["lineupBench-12"]
        scrollTo(bench, app: app)
        bench.tap()
        let midfield = app.buttons["pitchSlot-5"]
        scrollTo(midfield, app: app, towardTop: true)
        midfield.tap()
        XCTAssertTrue(midfield.label.contains("Finley"))
        let otherMidfield = app.buttons["pitchSlot-6"]
        let otherName = otherMidfield.label
        midfield.tap()
        XCTAssertEqual(midfield.value as? String, "Selected")
        let selectionShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())

        selectionShot.name = "Highlighted Player for Two-Tap Swap"
        selectionShot.lifetime = .keepAlways

        add(selectionShot)
        otherMidfield.tap()
        XCTAssertTrue(otherMidfield.label.contains("Finley"))
        XCTAssertEqual(midfield.label, otherName)
        otherMidfield.tap()
        midfield.tap()
        XCTAssertTrue(midfield.label.contains("Finley"))
        midfield.tap()
        app.buttons["Cancel Selection"].tap()
        XCTAssertNotEqual(midfield.value as? String, "Selected")
        let portraitShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())

        portraitShot.name = "Portrait Starting Lineup"
        portraitShot.lifetime = .keepAlways
        add(portraitShot)
        app.buttons["saveLineup"].tap()
        scrollTo(app.buttons["editStartingLineup"], app: app, towardTop: true)
        app.buttons["editStartingLineup"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-5"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Finley"))
        app.buttons["pitchSlot-0"].tap()
        XCTAssertEqual(app.buttons["pitchSlot-0"].value as? String, "Selected")
        app.buttons["pitchSlot-5"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Finley"))
        XCTAssertTrue(app.buttons["pitchSlot-5"].label.contains("Avery"))
        XCTAssertNotEqual(app.buttons["pitchSlot-0"].value as? String, "Selected")
        XCTAssertTrue(app.buttons["saveLineup"].isEnabled)
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["editStartingLineup"].tap()
        XCTAssertTrue(app.buttons["pitchSlot-0"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["pitchSlot-0"].label.contains("Avery"))
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["Cancel"].firstMatch.tap()
    }
    @MainActor func testGuestPlayersFromTeamThroughMatchSetup() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let addGuest = app.buttons["addGuestPlayer"]
        scrollTo(addGuest, app: app)
        XCTAssertTrue(addGuest.isHittable)
        addGuest.tap()
        try enterGuest(app, name: "Casey Guest", number: "80")
        app.buttons["guestPassType"].tap()
        app.buttons["Player Pass"].tap()
        let positionsShot = XCTAttachment(screenshot: app.screenshot())
        positionsShot.name = "Guest Position Controls"

        positionsShot.lifetime = .keepAlways
        add(positionsShot)
        let alternate = app.buttons["alsoPlays-ST"]
        app.collectionViews.firstMatch.swipeUp()
        scrollTo(alternate, app: app)
        alternate.tap()
        XCTAssertEqual(alternate.value as? String, "Selected")
        app.buttons["saveGuestPlayer"].tap()
        XCTAssertTrue(app.buttons["guestPlayer-80"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guestPlayer-80"].label.contains("ST"))
        XCTAssertFalse(app.buttons["teamPlayer-80"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Team Guest Players"

        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Match Day"].tap()
        app.buttons["Set Up a Match"].tap()
        let opponent = app.textFields["opponentField"]
        XCTAssertTrue(opponent.waitForExistence(timeout: 5))

        opponent.tap()
        opponent.typeText("Visitors\n")
        let rules = app.switches["I’ve Checked These Match Settings"]
        rules.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        scrollTo(app.buttons["addGuestPlayer"], app: app)
        app.buttons["addGuestPlayer"].tap()
        try enterGuest(app, name: "Jordan Guest", number: "81")
        app.buttons["saveGuestPlayer"].tap()
        XCTAssertTrue(app.buttons["guestPlayer-81"].waitForExistence(timeout: 5))
        app.buttons["createMatch"].tap()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 8))
        app.buttons["Match Options"].tap()
        app.buttons["Guest Players"].tap()
        XCTAssertTrue(app.buttons["guestPlayer-80"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guestPlayer-81"].exists)
        app.buttons["Done"].tap()
        scrollTo(app.buttons["Start Match"], app: app)
        app.buttons["Start Match"].tap()
        let incoming = app.buttons["matchBench-80"]
        scrollTo(incoming, app: app)
        XCTAssertTrue(incoming.isHittable)
    }
    @MainActor func testLateGuestJoinsLiveBenchAndFullScreenTools() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat", "--preview-full-match"]
        app.launch()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 8))
        app.buttons["Start Match"].tap()
        app.buttons["More"].tap()
        app.buttons["Guest Players"].tap()
        XCTAssertTrue(app.buttons["addGuestPlayer"].waitForExistence(timeout: 5))
        app.buttons["addGuestPlayer"].tap()
        try enterGuest(app, name: "Late Guest", number: "82")
        app.buttons["saveGuestPlayer"].tap()
        XCTAssertTrue(app.buttons["guestPlayer-82"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        let incoming = app.buttons["matchBench-82"]
        scrollTo(incoming, app: app)
        XCTAssertTrue(incoming.isHittable)

        incoming.tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Late Guest on Live Bench"

        shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor private func enterGuest(_ app: XCUIApplication, name: String, number: String) throws {
        let field = app.textFields["guestPlayerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name + "\n")
        let jersey = app.textFields["jerseyNumber"]
        jersey.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        jersey.typeText(number)
        app.buttons["jerseyNumberDone"].tap()
        XCTAssertTrue(app.buttons["saveGuestPlayer"].isEnabled)
    }
    @MainActor func testSetupFormationOptionsFollowTeamSize() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-setup", "--reset-setup-test", "--preview-flat"]
        app.launch()
        let name = app.textFields["setupTeamName"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Small Team\n")
        app.buttons["setupContinue"].tap()
        app.buttons["formationPicker"].tap()
        app.buttons["4–4–2"].tap()
        let decrement = app.steppers["setupFormat"].buttons.matching(NSPredicate(format: "label ENDSWITH 'Decrement'"))
            .firstMatch
        for _ in 0..<4 { decrement.tap() }
        XCTAssertEqual(app.buttons["formationPicker"].value as? String, "2–3–1")
        app.buttons["formationPicker"].tap()
        XCTAssertFalse(app.buttons["4–4–2"].exists)
        app.buttons["3–2–1"].tap()
        app.buttons["setupContinue"].tap()
        app.buttons["setupContinue"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3–2–1")).firstMatch.exists)
        app.buttons["setupContinue"].tap()
        app.buttons["Teams"].tap()
        app.buttons["Edit"].tap()
        XCTAssertEqual(app.buttons["formationPicker"].value as? String, "3–2–1")
    }
    @MainActor func testFormationSelectionAndNumericJerseyEntry() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-setup", "--reset-setup-test", "--preview-flat"]
        app.launch()
        let name = app.textFields["setupTeamName"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Formation Club\n")
        app.buttons["setupContinue"].tap()
        app.buttons["formationPicker"].tap()
        app.buttons["4–2–3–1"].tap()
        XCTAssertTrue(app.buttons["setupContinue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["formationPicker"].value as? String, "4–2–3–1")
        app.buttons["setupContinue"].tap()
        app.buttons["setupAddPlayer"].tap()
        let player = app.textFields["setupPlayerName"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        player.typeText("Casey\n")
        let number = app.textFields["jerseyNumber"]
        number.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        number.typeText(XCUIKeyboardKey.delete.rawValue + "100")
        XCTAssertFalse(app.buttons["setupSavePlayer"].isEnabled)
        number.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "42")
        XCTAssertEqual(number.value as? String, "42")
        app.buttons["jerseyNumberDone"].tap()
        app.buttons["setupSavePlayer"].tap()
        XCTAssertTrue(app.buttons["setupPlayer-42"].waitForExistence(timeout: 5))
        app.buttons["setupContinue"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "4–2–3–1")).firstMatch.exists)
        app.buttons["setupContinue"].tap()
        app.buttons["Teams"].tap()
        app.buttons["teamPlayer-42"].tap()
        XCTAssertTrue(number.waitForExistence(timeout: 5))
        number.tap()
        number.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "7")
        app.buttons["jerseyNumberDone"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["teamPlayer-7"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["formationPicker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["formationPicker"].value as? String, "4–2–3–1")
        app.buttons["formationPicker"].tap()
        app.buttons["4–4–2"].tap()
        app.buttons["Save"].tap()
        app.buttons["Match Day"].tap()
        app.buttons["Set Up a Match"].tap()
        XCTAssertTrue(app.buttons["formationPicker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["formationPicker"].value as? String, "4–4–2")
        app.buttons["formationPicker"].tap()
        app.buttons["3–5–2"].tap()
        XCTAssertEqual(app.buttons["formationPicker"].value as? String, "3–5–2")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Match Formation Selection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cancel"].tap()
    }
    @MainActor func testSetupKeyboardStaysOpenForEveryTeamField() throws {
        try verifySetupKeyboard(orientation: .landscapeLeft)
    }
    @MainActor func testSetupKeyboardInPortrait() throws {
        try verifySetupKeyboard(orientation: .portrait)
    }
    @MainActor private func verifySetupKeyboard(orientation: UIDeviceOrientation) throws {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-setup", "--reset-setup-test", "--preview-flat"]
        app.launch()
        for (label, value) in [
            ("Team Name", "Harbor Juniors"), ("Age Group (Optional)", "U12"), ("Season (Optional)", "Fall 2026"),
        ] {
            let field = app.textFields[label]
            XCTAssertTrue(field.waitForExistence(timeout: 8))
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard must open for \(label)")
            field.typeText(value)
            XCTAssertEqual(field.value as? String, value)
            XCTAssertTrue(app.keyboards.firstMatch.exists, "Keyboard must stay open after typing")
            XCTAssertLessThanOrEqual(
                field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1,
                "The active field must remain above the keyboard")
            app.keyboards.buttons["Done"].tap()
        }
        app.buttons["setupContinue"].tap()
        XCTAssertEqual(app.staticTexts["setupStepTitle"].label, "Match Defaults")
        app.buttons["setupBack"].tap()
        XCTAssertEqual(app.textFields["setupTeamName"].value as? String, "Harbor Juniors")
        XCTAssertEqual(app.textFields["Age Group (Optional)"].value as? String, "U12")
        XCTAssertEqual(app.textFields["Season (Optional)"].value as? String, "Fall 2026")
    }
    @MainActor func testOpenDashboardSurvivesResizeAndRotation() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat", "--exercise-resize"]
        app.launch()
        try XCTSkipUnless(
            min(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height) >= 600,
            "Requires the Duo inner display.")
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 8))
        app.buttons["Start Match"].tap()
        app.buttons["Goal For"].tap()
        for orientation: UIDeviceOrientation in [.portrait, .landscapeRight, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let resize = app.buttons["resizePreview"]
            resize.tap()
            XCTAssertEqual(resize.value as? String, "Compact")
            resize.tap()
            XCTAssertEqual(resize.value as? String, "Expanded")
            let field = app.otherElements["dashboardMatchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(field.frame.width, 240)
            XCTAssertGreaterThan(field.frame.height, 200)
            XCTAssertGreaterThanOrEqual(field.frame.minY, app.windows.firstMatch.frame.minY - 0.5)
            XCTAssertLessThanOrEqual(field.frame.maxY, app.windows.firstMatch.frame.maxY + 0.5)
            XCTAssertTrue(app.buttons["Match Options"].isHittable)
            XCTAssertTrue(app.buttons["fullScreenMatch"].isHittable)
            XCTAssertTrue(app.buttons["Pause"].isHittable)
            XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        }
    }
    @MainActor func testOpenFullScreenSurvivesCompactResize() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--preview-match", "--preview-full-match", "--preview-fold-book", "--exercise-resize",
            "--exercise-fold",
        ]
        app.launch()
        try XCTSkipUnless(
            min(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height) >= 600,
            "Requires the Duo inner display.")
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 8))
        app.buttons["Start Match"].tap()
        app.buttons["Goal For"].tap()
        for _ in 0..<3 {
            let resize = app.buttons["resizePreview"]
            resize.tap()
            XCTAssertTrue(app.otherElements["foldClearance"].waitForNonExistence(timeout: 5))
            XCTAssertGreaterThan(app.otherElements["fullScreenMatchField"].frame.width, 300)
            resize.tap()
            let field = app.otherElements["fullScreenMatchField"]
            XCTAssertGreaterThan(field.frame.width, 280)
            XCTAssertGreaterThan(field.frame.height, 180)
            XCTAssertGreaterThanOrEqual(field.frame.minY, app.windows.firstMatch.frame.minY - 0.5)
            XCTAssertLessThanOrEqual(field.frame.maxY, app.windows.firstMatch.frame.maxY + 0.5)
            XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
            cycleFoldPreview(app)
        }
    }
    @MainActor func testPracticePreservesEditsAcrossResizeAndFold() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--preview-board", "--preview-teaching", "--preview-fold-book", "--exercise-fold",
            "--exercise-resize",
        ]
        app.launch()
        try XCTSkipUnless(
            min(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height) >= 600,
            "Requires the Duo inner display.")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 8))
        app.buttons["Add"].tap()
        app.buttons["Ball"].tap()
        let field = app.otherElements["teachingField"]
        let edited = field.value as? String
        for _ in 0..<3 {
            let resize = app.buttons["resizePreview"]
            resize.tap()
            XCTAssertTrue(app.otherElements["foldClearance"].waitForNonExistence(timeout: 5))
            XCTAssertGreaterThan(field.frame.width, 300)
            XCTAssertEqual(field.value as? String, edited)
            resize.tap()
            XCTAssertGreaterThan(field.frame.width, 280)
            XCTAssertGreaterThan(field.frame.height, 180)
            XCTAssertGreaterThanOrEqual(field.frame.minX, app.windows.firstMatch.frame.minX - 0.5)
            XCTAssertGreaterThanOrEqual(field.frame.minY, app.windows.firstMatch.frame.minY - 0.5)
            XCTAssertLessThanOrEqual(field.frame.maxX, app.windows.firstMatch.frame.maxX + 0.5)
            XCTAssertLessThanOrEqual(field.frame.maxY, app.windows.firstMatch.frame.maxY + 0.5)
            XCTAssertEqual(field.value as? String, edited)
            cycleFoldPreview(app)
        }
        app.buttons["Undo"].tap()
        XCTAssertNotEqual(field.value as? String, edited)
        app.buttons["Redo"].tap()
        XCTAssertEqual(field.value as? String, edited)
    }
    @MainActor func testClosedDisplayIgnoresForcedFoldAndKeepsMatchUsable() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-full-match", "--preview-fold-book"]
        app.launch()
        try XCTSkipUnless(
            min(app.frame.width, app.frame.height) < 500, "Run this regression on the closed Duo or a compact iPhone.")
        XCTAssertTrue(app.buttons["exitMatchField"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["foldClearance"].exists)
        let field = app.otherElements["fullScreenMatchField"]
        XCTAssertGreaterThan(field.frame.width, 300)
        XCTAssertGreaterThan(field.frame.height, 240)
        let players = field.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pitchSlot-'"))
            .allElementsBoundByIndex
        XCTAssertEqual(players.count, 11)
        for (index, player) in players.enumerated() {
            XCTAssertTrue(player.isHittable, player.label)
            XCTAssertGreaterThanOrEqual(player.frame.width + 0.01, 44)
            XCTAssertGreaterThanOrEqual(player.frame.height + 0.01, 44)
            for other in players.dropFirst(index + 1) {
                XCTAssertFalse(player.frame.intersects(other.frame), "\(player.label) overlaps \(other.label)")
            }
        }
        for name in [
            "Start Match", "Goal For", "Goal Against", "Edit Starting Lineup", "End Half", "More", "Hide Controls",
        ] {
            let button = app.buttons[name]
            XCTAssertTrue(button.isHittable, name)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, name)
        }
        app.buttons["Start Match"].tap()
        app.buttons["Goal For"].tap()
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        app.buttons["Hide Controls"].tap()
        app.buttons["Controls"].tap()
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        XCTAssertTrue(app.buttons["matchBench-12"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Closed Display Match"

        shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor func testClosedDisplayPracticeToolsRemainReachable() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-board", "--preview-teaching", "--preview-fold-table"]
        app.launch()
        try XCTSkipUnless(
            min(app.frame.width, app.frame.height) < 500, "Run this regression on the closed Duo or a compact iPhone.")
        XCTAssertTrue(app.buttons["exitTeaching"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["foldClearance"].exists)
        let field = app.otherElements["teachingField"]
        XCTAssertGreaterThan(field.frame.width, 300)
        XCTAssertGreaterThan(field.frame.height, 300)
        for name in ["Move", "Draw", "Erase", "Arrow", "Add", "Undo", "Redo", "Hide Tools", "exitTeaching"] {
            XCTAssertTrue(app.buttons[name].isHittable, name)
            XCTAssertGreaterThanOrEqual(app.buttons[name].frame.height, 44, name)
        }
        let before = field.value as? String
        app.buttons["Add"].tap()
        app.buttons["Ball"].tap()
        XCTAssertNotEqual(field.value as? String, before)
        app.buttons["Undo"].tap()
        XCTAssertEqual(field.value as? String, before)
        app.buttons["Hide Tools"].tap()
        app.buttons["Tools"].tap()
        XCTAssertTrue(app.buttons["Draw"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Closed Display Practice"

        shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor func testPrivacyHelpAndConfirmedErasure() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let settings = app.buttons["Data & Settings"]
        scrollTo(settings, app: app)
        settings.tap()
        let privacy = app.buttons["Privacy Policy"]
        scrollTo(privacy, app: app)
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5))
        navigateBack(app)
        app.buttons["Coaching Guide"].tap()
        XCTAssertTrue(app.navigationBars["Coaching Guide"].waitForExistence(timeout: 5))
        navigateBack(app)
        let erase = app.buttons["Erase All Local Data"]
        scrollTo(erase, app: app)
        erase.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Data & Settings"].exists)
        erase.tap()
        app.alerts.buttons["Erase All Local Data"].tap()
        XCTAssertTrue(app.buttons["setupContinue"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["setupTeamName"].value as? String, "Team Name")
    }
    @MainActor func testSetupAccessibilityAudit() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        app.launchArguments = ["--uitesting-setup", "--reset-setup-test", "--preview-flat"]
        app.launch()
        XCTAssertTrue(app.buttons["setupContinue"].waitForExistence(timeout: 8))
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion])
    }
    @MainActor func testLargestTextMatchControlsStayReachable() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--preview-match", "--preview-flat", "--preview-full-match",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let start = app.buttons["Start Match"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isHittable)
        start.tap()
        XCTAssertTrue(app.buttons["Goal For"].isHittable)
        app.buttons["Goal For"].tap()
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        XCTAssertTrue(app.buttons["exitMatchField"].isHittable)
        scrollTo(app.buttons["Hide Controls"], app: app)
        app.buttons["Hide Controls"].tap()
        XCTAssertTrue(app.buttons["Controls"].isHittable)
        app.buttons["Controls"].tap()
        scrollTo(app.buttons["Pause"], app: app, towardTop: true)
        XCTAssertTrue(app.buttons["Pause"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Largest Text Match Controls"

        shot.lifetime = .keepAlways
        add(shot)
    }
    @MainActor func testBoardImageCanBeSavedThroughSystemShareSheet() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-board", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["Board Options"].waitForExistence(timeout: 8))
        app.buttons["Board Options"].tap()
        app.buttons["Export Board Image"].tap()
        let saveImage = app.cells["Save Image"]
        XCTAssertTrue(saveImage.waitForExistence(timeout: 8))
        scrollTo(saveImage, app: app)
        saveImage.tap()
        let permission = app.alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            let allow = permission.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Allow' OR label CONTAINS[c] 'Add Photos' OR label == 'OK'")
            ).firstMatch
            XCTAssertTrue(allow.exists)
            allow.tap()
        }
        XCTAssertTrue(app.buttons["Board Options"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.state, .runningForeground)
    }
    @MainActor func testFirstLaunchWizardResumesAndCreatesOnlyMyTeam() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-setup", "--reset-setup-test"]
        app.launch()
        let next = app.buttons["setupContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        XCTAssertFalse(next.isEnabled)
        let name = app.textFields["setupTeamName"]
        name.tap()
        name.typeText("Harbor Juniors")
        next.tap()
        XCTAssertEqual(app.staticTexts["setupStepTitle"].label, "Match Defaults")
        app.steppers["setupFormat"].buttons.matching(NSPredicate(format: "label ENDSWITH 'Decrement'")).firstMatch.tap()
        next.tap()
        XCTAssertEqual(app.staticTexts["setupStepTitle"].label, "Players")
        app.buttons["setupAddPlayer"].tap()
        let playerName = app.textFields["setupPlayerName"]
        XCTAssertTrue(playerName.waitForExistence(timeout: 5))
        playerName.tap()
        playerName.typeText("Casey\n")
        let alternate = app.buttons["alsoPlays-ST"]
        scrollTo(alternate, app: app)
        alternate.tap()
        app.buttons["setupSavePlayer"].tap()
        XCTAssertTrue(app.buttons["setupPlayer-1"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--uitesting-setup"]
        app.launch()
        XCTAssertTrue(app.buttons["setupPlayer-1"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["setupStepTitle"].label, "Players")
        next.tap()
        XCTAssertEqual(app.staticTexts["setupStepTitle"].label, "Review")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Harbor Juniors'")).firstMatch
                .waitForExistence(timeout: 5))
        app.buttons["setupBack"].tap()
        XCTAssertTrue(app.buttons["setupPlayer-1"].exists)
        next.tap()
        next.tap()
        XCTAssertTrue(app.buttons["Set Up a Match"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Set Up a Match"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["setupContinue"].exists)
        app.buttons["Teams"].tap()
        let player = app.buttons["teamPlayer-1"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(player.label.contains("Casey"))
        XCTAssertFalse(app.buttons["teamPlayer-2"].exists)
        player.tap()
        let position = app.buttons["alsoPlays-ST"]
        scrollTo(position, app: app)
        XCTAssertEqual(position.value as? String, "Selected")
        app.buttons["Cancel"].tap()
        app.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Your Playbook Starts Here"].waitForExistence(timeout: 5))
    }
    @MainActor func testSetupCanDeferRosterAndOpenTeams() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-setup", "--reset-setup-test"]
        app.launch()
        let name = app.textFields["setupTeamName"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("Weekend Team")
        let next = app.buttons["setupContinue"]
        next.tap()
        next.tap()
        XCTAssertEqual(next.label, "Add Players Later")
        next.tap()
        next.tap()
        XCTAssertTrue(app.buttons["Add Players"].waitForExistence(timeout: 8))
        app.buttons["Add Players"].tap()
        XCTAssertTrue(app.buttons["Add Player"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["teamPlayer-1"].exists)
    }
    @MainActor func testMatchDayWorkflow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Set Up a Match"].tap()
        let opponent = app.textFields["opponentField"]
        XCTAssertTrue(opponent.waitForExistence(timeout: 5))

        opponent.tap()
        opponent.typeText("Westside\n")
        let rules = app.switches["I’ve Checked These Match Settings"]
        rules.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(rules.value as? String, "1")
        let create = app.buttons["createMatch"]
        XCTAssertTrue(create.waitForExistence(timeout: 3))

        XCTAssertTrue(create.isEnabled)
        create.tap()
        let start = app.buttons["Start Match"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        scrollTo(start, app: app)
        start.tap()
        let liveShot = XCTAttachment(screenshot: app.screenshot())
        liveShot.name = "Live match"

        liveShot.lifetime = .keepAlways
        add(liveShot)
        let goal = app.buttons["Goal For"]
        scrollTo(goal, app: app)
        goal.tap()
        scrollTo(app.staticTexts["score"], app: app)
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        let incoming = app.buttons["matchBench-12"]
        scrollTo(incoming, app: app)
        incoming.tap()
        let outgoing = app.buttons["pitchSlot-0"]
        scrollTo(outgoing, app: app, towardTop: true)
        outgoing.tap()
        XCTAssertFalse(app.buttons["Confirm Players Are on the Field"].exists)
        scrollTo(app.buttons["End Half"], app: app)
        app.buttons["End Half"].tap()
        app.buttons.matching(identifier: "confirmEndPeriod").firstMatch.tap()
        scrollTo(app.buttons["Start Second Half"], app: app)
        app.buttons["Start Second Half"].tap()
        app.buttons["Full Time"].tap()
        app.buttons.matching(identifier: "confirmEndPeriod").firstMatch.tap()
        XCTAssertTrue(app.buttons["Share Report Without Names"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Completed match"

        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor func testBoardAndTeamNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Practice"].tap()
        app.buttons["Open a fresh board"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 5))
        app.buttons["Draw"].tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4)),
            end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        app.buttons["Move"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Practice Board"

        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["showPlayers"].tap()
        assertFullScreenField(app)
        XCTAssertTrue(app.buttons["Draw"].isHittable)
        app.buttons["exitTeaching"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Library"].tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Untitled Practice'")).firstMatch.exists)
        app.buttons["Teams"].tap()
        XCTAssertTrue(app.buttons["Add Team"].exists)
        let settings = app.buttons["Data & Settings"]
        scrollTo(settings, app: app)
        settings.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'PitchHarbor works offline'")).firstMatch
                .waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export Editable Backup"].exists)
        let branding = XCTAttachment(screenshot: app.screenshot())
        branding.name = "PitchHarbor settings"

        branding.lifetime = .keepAlways
        add(branding)
    }
    @MainActor func testTeachingFieldAdaptsToOrientation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-board", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["showPlayers"].waitForExistence(timeout: 8))
        app.buttons["showPlayers"].tap()
        for orientation: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            assertFullScreenField(app)
            let shot = XCTAttachment(screenshot: app.screenshot())

            shot.name = "Full-screen field \(orientation.rawValue)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        app.buttons["exitTeaching"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 5))
    }
    @MainActor func testSmartSubImmediateSwapAndUndo() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-subs"]
        app.launch()
        let plan = app.buttons["rotationPlan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        scrollTo(plan, app: app)
        plan.tap()
        let target = app.steppers["stintTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.buttons.matching(NSPredicate(format: "label ENDSWITH 'Increment'")).firstMatch.tap()
        app.buttons["saveRotationPlan"].tap()
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewSmartSub-'")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        scrollTo(review, app: app)
        let reviewID = review.identifier
        review.tap()
        XCTAssertFalse(app.buttons["Confirm Players Are on the Field"].exists)
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[reviewID].exists)
        let undo = app.buttons["Undo"]
        scrollTo(undo, app: app)
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertTrue(app.buttons[reviewID].waitForExistence(timeout: 5))
        scrollTo(plan, app: app)
        plan.tap()
        let player = app.buttons["rotationPlayer-14"]
        scrollTo(player, app: app, towardTop: true)
        player.tap()
        let alternate = app.buttons["alsoPlays-CM"]
        scrollTo(alternate, app: app)
        alternate.tap()
        XCTAssertEqual(alternate.value as? String, "Selected")
        let ready = app.switches["rotationReady"]
        scrollTo(ready, app: app)
        ready.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(ready.value as? String, "0")
        navigateBack(app)
        app.buttons["saveRotationPlan"].tap()
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reviewSmartSub-14"].exists)
    }
    @MainActor func testRosterMultiplePositionsPersist() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let player = app.buttons["teamPlayer-12"]
        scrollTo(player, app: app)
        player.tap()
        for role in ["RB", "ST"] {
            let position = app.buttons["alsoPlays-\(role)"]
            scrollTo(position, app: app)
            position.tap()
            XCTAssertEqual(position.value as? String, "Selected")
        }
        let preferred = app.buttons["preferredPosition"]
        scrollTo(preferred, app: app, towardTop: true)
        preferred.tap()
        app.buttons["ST · Striker"].tap()
        XCTAssertEqual(preferred.value as? String, "ST, Striker")
        let midfield = app.buttons["alsoPlays-CM"]
        scrollTo(midfield, app: app)
        XCTAssertEqual(midfield.value as? String, "Selected")
        scrollTo(preferred, app: app, towardTop: true)
        preferred.tap()
        app.buttons["CM · Central Midfield"].tap()
        XCTAssertEqual(preferred.value as? String, "CM, Central Midfield")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Multiple approved positions"

        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Save"].tap()
        scrollTo(player, app: app)
        player.tap()
        for role in ["RB", "ST"] {
            let position = app.buttons["alsoPlays-\(role)"]
            scrollTo(position, app: app)
            XCTAssertEqual(position.value as? String, "Selected")
        }
        let back = app.buttons["alsoPlays-RB"]
        scrollTo(back, app: app)
        back.tap()
        XCTAssertEqual(back.value as? String, "Not Selected")
        app.buttons["Save"].tap()
        scrollTo(player, app: app)
        player.tap()
        scrollTo(app.buttons["alsoPlays-RB"], app: app)
        XCTAssertEqual(app.buttons["alsoPlays-RB"].value as? String, "Not Selected")
        scrollTo(app.buttons["alsoPlays-ST"], app: app)
        XCTAssertEqual(app.buttons["alsoPlays-ST"].value as? String, "Selected")
        app.buttons["Cancel"].tap()
    }
    @MainActor func testFullScreenMatchControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["Hide Toolbar"].waitForExistence(timeout: 8))
        app.buttons["Hide Toolbar"].tap()
        XCTAssertFalse(app.buttons["Start Match"].exists)
        XCTAssertTrue(app.staticTexts["score"].exists)
        app.buttons["Show Toolbar"].tap()
        XCTAssertTrue(app.buttons["Start Match"].exists)
        let expand = app.buttons["fullScreenMatch"]
        XCTAssertTrue(expand.waitForExistence(timeout: 8))
        scrollTo(expand, app: app)
        expand.tap()
        XCTAssertTrue(app.buttons["exitMatchField"].waitForExistence(timeout: 5))
        for title in ["Start Match", "Goal For", "Goal Against", "Edit Starting Lineup", "End Half", "Undo", "More"] {
            XCTAssertTrue(app.buttons[title].isHittable, title)
        }
        app.buttons["Start Match"].tap()
        app.buttons["Goal For"].tap()
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        let field = app.otherElements["fullScreenMatchField"]
        let visibleArea = field.frame.width * field.frame.height
        app.buttons["Hide Controls"].tap()
        XCTAssertFalse(app.buttons["Goal For"].exists)
        XCTAssertFalse(app.staticTexts["score"].exists)
        XCTAssertGreaterThan(field.frame.width * field.frame.height, visibleArea)
        XCTAssertTrue(app.buttons["Controls"].isHittable)
        app.buttons["Controls"].tap()
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        XCTAssertTrue(app.buttons["Pause"].exists)
        let incoming = app.buttons["matchBench-12"]
        scrollTo(incoming, app: app)
        incoming.tap()
        let outgoing = app.buttons["pitchSlot-0"]
        scrollTo(outgoing, app: app, towardTop: true)
        outgoing.tap()
        XCTAssertFalse(app.buttons["Confirm Players Are on the Field"].exists)
        XCTAssertTrue(app.buttons["exitMatchField"].waitForExistence(timeout: 5))
        app.buttons["Undo"].tap()
        app.buttons["End Half"].tap()
        app.buttons.matching(identifier: "confirmEndPeriod").firstMatch.tap()
        XCTAssertTrue(app.buttons["Start Second Half"].waitForExistence(timeout: 5))

        app.buttons["Start Second Half"].tap()
        app.buttons["More"].tap()
        app.buttons["Smart Subs & Bench"].tap()
        XCTAssertTrue(app.buttons["rotationPlan"].waitForExistence(timeout: 5))
        app.buttons["rotationPlan"].tap()
        XCTAssertTrue(app.buttons["saveRotationPlan"].waitForExistence(timeout: 5))

        app.buttons["saveRotationPlan"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["exitMatchField"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Full-screen match toolbar"

        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Full Time"].tap()
        app.buttons.matching(identifier: "confirmEndPeriod").firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "identifier == 'matchPhase' AND label BEGINSWITH 'Full Time'"))
                .firstMatch.waitForExistence(timeout: 5))
        app.buttons["exitMatchField"].tap()
        XCTAssertTrue(app.buttons["Share Report Without Names"].waitForExistence(timeout: 5))
    }
    @MainActor func testCompactLandscapeMatchField() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-match", "--preview-full-match"]

        app.launch()
        XCTAssertTrue(app.buttons["exitMatchField"].waitForExistence(timeout: 8))
        let jordan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Jordan, number'")).firstMatch
        let riley = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Riley, number'")).firstMatch
        XCTAssertTrue(jordan.isHittable)
        XCTAssertTrue(riley.isHittable)
        XCTAssertFalse(jordan.frame.intersects(riley.frame))
        XCTAssertTrue(app.buttons["Start Match"].isHittable)
        XCTAssertTrue(app.buttons["Edit Starting Lineup"].isHittable)
        XCTAssertTrue(app.buttons["More"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Compact landscape match"

        shot.lifetime = .keepAlways
        add(shot)
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testFullScreenPracticeTools() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--preview-board", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["showPlayers"].waitForExistence(timeout: 8))
        let editingField = app.otherElements["editingField"]
        let editingArea = editingField.frame.width * editingField.frame.height
        app.buttons["Hide Tools"].tap()
        XCTAssertGreaterThan(editingField.frame.width * editingField.frame.height, editingArea)
        XCTAssertFalse(app.buttons["Draw"].exists)
        app.buttons["Tools"].tap()
        XCTAssertTrue(app.buttons["Draw"].isHittable)
        app.buttons["showPlayers"].tap()
        XCTAssertTrue(app.buttons["exitTeaching"].waitForExistence(timeout: 5))
        app.buttons["Add"].tap()
        app.buttons["Ball"].tap()
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["Redo"].isEnabled)
        app.buttons["Redo"].tap()
        app.buttons["Arrow"].tap()
        let field = app.otherElements["teachingField"]
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).press(
            forDuration: 0.1, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        XCTAssertTrue((field.value as? String)?.contains("3 arrows") == true)
        app.buttons["Undo"].tap()
        XCTAssertTrue((field.value as? String)?.contains("2 arrows") == true)
        app.buttons["Redo"].tap()
        XCTAssertTrue((field.value as? String)?.contains("3 arrows") == true)
        let visibleArea = field.frame.width * field.frame.height
        app.buttons["Hide Tools"].tap()
        XCTAssertFalse(app.buttons["Draw"].exists)
        XCTAssertGreaterThan(field.frame.width * field.frame.height, visibleArea)
        XCTAssertTrue((field.value as? String)?.contains("3 arrows") == true)
        XCTAssertTrue(app.buttons["Tools"].isHittable)
        app.buttons["Tools"].tap()
        XCTAssertTrue(app.buttons["Draw"].isHittable)
        app.buttons["exitTeaching"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }
    @MainActor func testFoldedMatchPanelsPreserveGameAcrossPoses() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--preview-match", "--preview-full-match", "--preview-fold-book", "--exercise-fold",
        ]
        app.launch()
        try XCTSkipUnless(
            min(app.frame.width, app.frame.height) >= 600,
            "This transition test requires a Duo-sized window; compact fallback is covered by geometry tests.")
        let field = app.otherElements["fullScreenMatchField"]
        XCTAssertTrue(app.buttons["swapFoldPanels"].waitForExistence(timeout: 8))
        assertOutsideFold(field, app: app)
        app.buttons["Start Match"].tap()
        app.buttons["Goal For"].tap()
        let original = field.frame
        app.buttons["swapFoldPanels"].tap()
        XCTAssertGreaterThan(field.frame.minX, original.minX)
        assertOutsideFold(field, app: app)
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        // Tabletop moves the same content above/below the actual usable-region boundary.
        cycleFoldPreview(app)
        assertOutsideFold(field, app: app)
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        cycleFoldPreview(app)
        XCTAssertTrue(app.otherElements["foldClearance"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        XCTAssertTrue(app.buttons["Pause"].exists)
        cycleFoldPreview(app)
        assertOutsideFold(field, app: app)
        let hide = app.buttons["Hide Controls"]
        scrollTo(hide, app: app)
        hide.tap()
        XCTAssertTrue(app.buttons["Controls"].isHittable)
        app.buttons["Controls"].tap()
        XCTAssertEqual(app.staticTexts["score"].label, "1  :  0")
        let bench = app.buttons["benchDetail-12"]
        scrollTo(bench, app: app)
        XCTAssertTrue(bench.isHittable)
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor func testFoldedBoardPreservesEditsAcrossPoses() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--preview-board", "--preview-teaching", "--preview-fold-book", "--exercise-fold",
        ]
        app.launch()
        try XCTSkipUnless(
            min(app.frame.width, app.frame.height) >= 600,
            "This transition test requires a Duo-sized window; compact fallback is covered by geometry tests.")
        let field = app.otherElements["teachingField"]
        XCTAssertTrue(app.buttons["swapFoldPanels"].waitForExistence(timeout: 8))
        assertOutsideFold(field, app: app)
        app.buttons["Add"].tap()
        app.buttons["Ball"].tap()
        app.buttons["Arrow"].tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).press(
            forDuration: 0.1, thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        let edited = field.value as? String
        XCTAssertTrue(edited?.contains("3 arrows") == true)
        app.buttons["swapFoldPanels"].tap()
        assertOutsideFold(field, app: app)
        XCTAssertEqual(field.value as? String, edited)
        cycleFoldPreview(app)
        assertOutsideFold(field, app: app)
        XCTAssertEqual(field.value as? String, edited)
        cycleFoldPreview(app)
        XCTAssertTrue(app.otherElements["foldClearance"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, edited)
        app.buttons["Undo"].tap()
        XCTAssertTrue((field.value as? String)?.contains("2 arrows") == true)
        app.buttons["Redo"].tap()
        XCTAssertEqual(field.value as? String, edited)
        cycleFoldPreview(app)
        let hide = app.buttons["Hide Tools"]
        scrollTo(hide, app: app)
        hide.tap()
        XCTAssertTrue(app.buttons["Tools"].isHittable)
        app.buttons["Tools"].tap()
        XCTAssertEqual(field.value as? String, edited)
        XCUIDevice.shared.orientation = .portrait
    }
    @MainActor private func navigateBack(_ app: XCUIApplication) {
        // Duo places this in its vertical Toolbar, outside the NavigationBar subtree.
        let verticalBack = app.buttons["BackButton"]
        if verticalBack.exists { verticalBack.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
    }
    @MainActor private func cycleFoldPreview(_ app: XCUIApplication) {
        let button = app.buttons.matching(identifier: "cycleFoldPreview").allElementsBoundByIndex.first {
            $0.isHittable
        }!
        let before = button.value as? String
        button.tap()
        let expected = before == "Book" ? "Tabletop" : (before == "Tabletop" ? "Flat" : "Book")
        XCTAssertEqual(button.value as? String, expected)
    }
    @MainActor private func assertOutsideFold(_ field: XCUIElement, app: XCUIApplication) {
        let crease = app.otherElements["foldClearance"]
        XCTAssertTrue(crease.waitForExistence(timeout: 5))
        XCTAssertFalse(field.frame.intersects(crease.frame))
        for button in app.buttons.allElementsBoundByIndex where button.isHittable {
            XCTAssertFalse(button.frame.intersects(crease.frame), button.label)
        }
    }
    @MainActor private func assertFullScreenField(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["exitTeaching"].waitForExistence(timeout: 5))
        let field = app.otherElements["teachingField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let screenEdges = [app.frame.width, app.frame.height].sorted()
        let fieldEdges = [field.frame.width, field.frame.height].sorted()
        XCTAssertGreaterThan(fieldEdges[0], screenEdges[0] * 0.6)
        XCTAssertGreaterThan(fieldEdges[1], screenEdges[1] * 0.75)
        XCTAssertTrue(app.buttons["Draw"].isHittable)
        XCTAssertTrue(app.buttons["Add"].isHittable)
        XCTAssertTrue(app.buttons["exitTeaching"].isHittable)
    }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        if element.isHittable { return }
        // Scroll the foreground container; application coordinates can remain
        // portrait-based while Duo displays a landscape scene.
        let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex
        // Ignore short horizontal team selectors when seeking an item below the page.
        let scroller = containers.last(where: { $0.isHittable && $0.frame.height >= 150 }) ?? app
        for _ in 0..<12 {
            if element.isHittable { return }
            // Use the target's location instead of pulling down at the top of
            // a sheet, which is the system's interactive dismissal gesture.
            // Lazy Form rows may be absent from the hierarchy after scrolling away.
            if towardTop || (element.exists && element.frame.maxY < scroller.frame.minY + 20) {
                scroller.swipeDown()
            } else {
                scroller.swipeUp()
            }
        }
    }
}
