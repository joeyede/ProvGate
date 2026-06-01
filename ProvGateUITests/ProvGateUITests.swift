import XCTest

// MARK: - Helpers

private extension XCUIApplication {
    static func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
        return app
    }

    static func launchForceConnecting() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestForceConnecting"]
        app.launch()
        return app
    }

    static func launchForceConnected() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestForceConnected"]
        app.launch()
        return app
    }
}

// MARK: - Login Screen

final class LoginScreenTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = .launchClean()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testLoginFormElementsExist() {
        XCTAssert(app.textFields["Username"].waitForExistence(timeout: 3))
        XCTAssert(app.secureTextFields["Password"].exists)
        XCTAssert(app.switches["Remember me"].exists)
        XCTAssert(app.buttons["Connect"].exists)
    }

    func testTitleAndVersionDisplayed() {
        XCTAssert(app.staticTexts["Gate Control"].waitForExistence(timeout: 3))
        let versionLabels = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'v'"))
        XCTAssert(versionLabels.firstMatch.waitForExistence(timeout: 3))
    }

    func testConnectButtonDisabledWhenFieldsEmpty() {
        _ = app.textFields["Username"].waitForExistence(timeout: 3)
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
    }

    func testConnectButtonDisabledWhenOnlyUsernameFilled() {
        let username = app.textFields["Username"]
        _ = username.waitForExistence(timeout: 3)
        username.tap()
        username.typeText("testuser")
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
    }

    func testConnectButtonDisabledWhenOnlyPasswordFilled() {
        _ = app.secureTextFields["Password"].waitForExistence(timeout: 3)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("testpass")
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
    }

    func testConnectButtonEnabledWhenBothFieldsFilled() {
        let username = app.textFields["Username"]
        _ = username.waitForExistence(timeout: 3)
        username.tap()
        username.typeText("testuser")

        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("testpass")

        XCTAssert(app.buttons["Connect"].isEnabled)
    }

    func testPasswordShowHideToggle() {
        _ = app.secureTextFields["Password"].waitForExistence(timeout: 3)

        // Initially: secure field visible, plain field absent
        XCTAssert(app.secureTextFields["Password"].exists)
        XCTAssertFalse(app.textFields["Password"].exists)

        // Reveal password
        app.buttons["showPasswordToggle"].tap()
        XCTAssert(app.textFields["Password"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.secureTextFields["Password"].exists)

        // Hide again
        app.buttons["showPasswordToggle"].tap()
        XCTAssert(app.secureTextFields["Password"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.textFields["Password"].exists)
    }

    func testRememberMeToggleDefaultsOff() {
        _ = app.switches["Remember me"].waitForExistence(timeout: 3)
        XCTAssertEqual(app.switches["Remember me"].value as? String, "0")
    }

    func testRememberMeToggleCanBeEnabled() {
        let toggle = app.switches["Remember me"]
        _ = toggle.waitForExistence(timeout: 3)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }
}

// MARK: - Connecting Screen

final class ConnectingScreenTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = .launchForceConnecting()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testConnectingScreenElementsExist() {
        XCTAssert(app.staticTexts["Gate Control"].waitForExistence(timeout: 3))
        XCTAssert(app.staticTexts["Connecting..."].waitForExistence(timeout: 3))
        XCTAssert(app.staticTexts["Restoring your session"].waitForExistence(timeout: 3))
    }

    func testConnectingScreenHasNoGateButtons() {
        _ = app.staticTexts["Gate Control"].waitForExistence(timeout: 3)
        XCTAssertFalse(app.buttons["Full Open"].exists)
        XCTAssertFalse(app.buttons["Pedestrian"].exists)
    }
}

// MARK: - Gate Control Screen

final class GateControlScreenTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = .launchForceConnected()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testAllFourGateButtonsExist() {
        XCTAssert(app.buttons["Pedestrian"].waitForExistence(timeout: 3))
        XCTAssert(app.buttons["Full Open"].exists)
        XCTAssert(app.buttons["Left"].exists)
        XCTAssert(app.buttons["Right"].exists)
    }

    func testGateButtonsAreEnabled() {
        _ = app.buttons["Full Open"].waitForExistence(timeout: 3)
        XCTAssert(app.buttons["Pedestrian"].isEnabled)
        XCTAssert(app.buttons["Full Open"].isEnabled)
        XCTAssert(app.buttons["Left"].isEnabled)
        XCTAssert(app.buttons["Right"].isEnabled)
    }

    func testLogoutButtonExists() {
        XCTAssert(app.buttons["Log out"].waitForExistence(timeout: 3))
    }

    func testLogoutTransitionsToLoginScreen() {
        _ = app.buttons["Log out"].waitForExistence(timeout: 3)
        app.buttons["Log out"].tap()
        XCTAssert(app.textFields["Username"].waitForExistence(timeout: 3))
        XCTAssert(app.buttons["Connect"].exists)
    }

    func testDryRunBadgeVisibleInForceConnectedMode() {
        // -UITestForceConnected sets isDryRun=true, so the badge should be shown
        XCTAssert(app.staticTexts["DRY RUN"].waitForExistence(timeout: 3))
    }

    func testInsideOutsideToggleExists() {
        XCTAssert(app.staticTexts["Inside"].waitForExistence(timeout: 3))
        XCTAssert(app.staticTexts["Outside"].exists)
        XCTAssert(app.switches.firstMatch.exists)
    }

    func testDebugSheetOpensOnLongPress() {
        let title = app.staticTexts["Gate Control"]
        _ = title.waitForExistence(timeout: 3)
        title.press(forDuration: 0.8)
        XCTAssert(app.staticTexts["Debug"].waitForExistence(timeout: 3))
        XCTAssert(app.staticTexts["Dry Run"].exists)
    }

    func testStatusMessageShownWhenNotConnected() {
        // Tap a button — force-connected has no real MQTT client, so sendCommand
        // falls through to "Not connected" (client is nil)
        _ = app.buttons["Full Open"].waitForExistence(timeout: 3)
        app.buttons["Full Open"].tap()
        // Toast notification should appear briefly
        XCTAssert(app.staticTexts["Not connected to MQTT"].waitForExistence(timeout: 3))
    }
}
