// Opt-in marketing captures coordinated with AppStore/source/capture.py.
// The host selects the simulator display; these tests hold each fixture screen until captured.

import XCTest

/// Run explicitly to refresh the real-app imagery used by AppStore/source.
final class AppStoreScreenCaptureTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testCaptureDuoFeatures() throws {
        let enabled = URL.temporaryDirectory.appending(path: "PitchHarborCapture.enabled")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: enabled.path),
            "Start AppStore/source/capture.py to opt into marketing captures.")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["--app-store-capture", "--preview-flat"]
        app.launch()
        XCTAssertTrue(app.buttons["rotationPlan"].waitForExistence(timeout: 10))
        capture("01-match-day", app)
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewSmartSub-'")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if review.isHittable { break }
            app.swipeUp()
        }
        capture("02-smart-subs", app)
        app.buttons["Full Screen"].tap()
        XCTAssertTrue(app.otherElements["fullScreenMatchField"].waitForExistence(timeout: 5))
        capture("03-full-pitch", app)
        app.terminate()
        app.launchArguments = ["--app-store-capture", "--preview-flat", "--preview-board", "--preview-teaching"]
        app.launch()
        XCTAssertTrue(app.buttons["exitTeaching"].waitForExistence(timeout: 8))
        capture("04-practice-board", app)
        app.buttons["Hide Tools"].tap()
        capture("04b-teaching-field", app)
        app.terminate()
        app.launchArguments = ["--app-store-capture", "--preview-flat"]
        app.launch()
        app.buttons["Teams"].tap()
        let player = app.buttons["teamPlayer-12"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        let alternate = app.buttons["alsoPlays-ST"]
        let containers = app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex
        let scroller = containers.last(where: { $0.isHittable && $0.frame.height >= 150 }) ?? app
        for _ in 0..<12 {
            if alternate.isHittable { break }
            scroller.swipeUp()
        }
        XCTAssertTrue(alternate.isHittable)
        capture("05-player-positions", app)
        app.buttons["Cancel"].tap()
        app.buttons["Library"].tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Build From the Back'")).firstMatch
                .waitForExistence(timeout: 5))
        capture("06-playbook", app)
        app.terminate()
        app.launchArguments = ["--uitesting-setup", "--reset-setup-test", "--preview-flat"]
        app.launch()
        XCTAssertTrue(app.buttons["setupContinue"].waitForExistence(timeout: 8))
        capture("07-get-started", app)
    }
    @MainActor func testCapturePhoneFeatures() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: URL.temporaryDirectory.appending(path: "PitchHarborCapture.enabled").path),
            "Start the phone capture host script first.")
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--app-store-capture", "--preview-flat"]
        app.launch()
        XCTAssertTrue(app.buttons["rotationPlan"].waitForExistence(timeout: 8))
        capture("01-match-day", app)
        let review = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewSmartSub-'")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if review.isHittable { break }
            app.swipeUp()
        }
        capture("02-smart-subs", app)
        app.terminate()

        app.launchArguments = ["--app-store-capture", "--preview-flat", "--preview-board", "--preview-teaching"]

        app.launch()
        XCTAssertTrue(app.buttons["exitTeaching"].waitForExistence(timeout: 8))
        capture("03-practice", app)
        app.terminate()
        app.launchArguments = ["--uitesting-setup", "--reset-setup-test", "--preview-flat"]

        app.launch()
        XCTAssertTrue(app.buttons["setupContinue"].waitForExistence(timeout: 8))
        capture("04-setup", app)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        // XCUIScreenshot currently returns the inactive Duo display. The host
        // capture script targets display 3 while this handshake holds the UI.
        let ready = URL.temporaryDirectory.appending(path: "PitchHarborCapture-" + name + ".ready")
        try! Data(name.utf8).write(to: ready)
        let deadline = Date().addingTimeInterval(45)
        while FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ready.path),
            "Run AppStore/source/capture.py alongside this capture test.")
    }
}
