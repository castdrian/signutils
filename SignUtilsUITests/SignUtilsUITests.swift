import XCTest

@MainActor
final class SignUtilsUITests: XCTestCase {
    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    func testOnboardingOffersKeyAndDemo() {
        let app = launch([])
        XCTAssertTrue(app.buttons["addKey"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["exploreDemo"].exists)
        press(app.buttons["addKey"])
        XCTAssertTrue(app.textFields["keyID"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connect"].isEnabled)
    }

    func testCreatesAndRevokesASigningBundle() {
        let app = launch(["-demo"])
        let newBundle = app.buttons["newBundle"]
        XCTAssertTrue(newBundle.waitForExistence(timeout: 20))
        press(newBundle)

        tap(app.buttons["kind-development"])
        advance(app)

        press(app.buttons["New"].firstMatch)
        let identifier = app.textFields["newIdentifier"]
        XCTAssertTrue(identifier.waitForExistence(timeout: 5))
        type("com.demo.uitest", into: identifier)
        advance(app)

        toggle(app, "capability-APP_GROUPS")
        toggle(app, "capability-PUSH_NOTIFICATIONS")
        advance(app)

        tap(app.buttons["selectAllDevices"])
        let name = app.textFields["newDeviceName"]
        scrollTo(name, in: app)
        type("UI Test iPhone\n", into: name)
        app.typeText("00008120-000A1B2C3D4E5F60\n")
        XCTAssertTrue(app.staticTexts["00008120-000A1B2C3D4E5F60"].waitForExistence(timeout: 5))
        advance(app)

        tap(app.buttons["newCertificate"])
        advance(app)

        let generate = app.buttons["generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        press(generate)
        XCTAssertTrue(app.descendants(matching: .any)["generationSucceeded"].waitForExistence(timeout: 30))
        tap(app.buttons["finish"])

        let row = app.descendants(matching: .any).matching(identifier: "libraryRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["com.demo.uitest"].exists || row.label.contains("com.demo.uitest"))
        press(row)

        let revoke = app.buttons["revokeAll"]
        scrollTo(revoke, in: app)
        press(revoke)
        let confirm = app.buttons["Revoke"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        press(confirm)
        XCTAssertTrue(app.staticTexts["Certificate revoked"].waitForExistence(timeout: 15))
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["revokeAll"])
        waitForExpectations(timeout: 15)
    }

    func testReviewWalkthrough() {
        #if os(iOS)
            XCUIDevice.shared.press(.home)
            linger(3)
        #endif
        let app = launch([])
        let demo = app.buttons["exploreDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 20))
        linger(3)
        press(app.buttons["addKey"])
        XCTAssertTrue(app.textFields["keyID"].waitForExistence(timeout: 5))
        linger(3)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        linger()
        press(demo)

        let newBundle = app.buttons["newBundle"]
        XCTAssertTrue(newBundle.waitForExistence(timeout: 30))
        linger(3)
        press(newBundle)

        tap(app.buttons["kind-development"])
        linger()
        advance(app)

        tap(app.buttons["bundle-com.demo.fieldnotes"])
        linger()
        advance(app)

        XCTAssertTrue(app.switches["capability-APP_GROUPS"].waitForExistence(timeout: 10))
        linger()
        toggle(app, "capability-APP_GROUPS")
        toggle(app, "capability-PUSH_NOTIFICATIONS")
        linger()
        advance(app)

        tap(app.buttons["selectAllDevices"])
        linger()
        let name = app.textFields["newDeviceName"]
        scrollTo(name, in: app)
        type("Review iPhone\n", into: name)
        app.typeText("00008130-000A1B2C3D4E5F60\n")
        XCTAssertTrue(app.staticTexts["00008130-000A1B2C3D4E5F60"].waitForExistence(timeout: 5))
        linger()
        advance(app)

        tap(app.buttons["newCertificate"])
        linger()
        advance(app)

        let generate = app.buttons["generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        linger(3)
        press(generate)
        XCTAssertTrue(app.descendants(matching: .any)["generationSucceeded"].waitForExistence(timeout: 30))
        linger(4)
        tap(app.buttons["finish"])

        let row = app.descendants(matching: .any).matching(identifier: "libraryRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        linger()
        press(row)

        let share = app.buttons["shareArchive"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        linger(3)
        press(share)
        linger(3)
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        linger()

        let revoke = app.buttons["revokeAll"]
        scrollTo(revoke, in: app)
        linger()
        press(revoke)
        let confirm = app.buttons["Revoke"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        linger()
        press(confirm)
        XCTAssertTrue(app.staticTexts["Certificate revoked"].waitForExistence(timeout: 15))
        linger(3)
        navigateBack(app)
        linger()

        for tab in ["Certificates", "Profiles", "App IDs", "Devices", "Library"] {
            let button = app.tabBars.buttons[tab]
            guard button.waitForExistence(timeout: 5) else { continue }
            button.tap()
            linger(3)
        }
    }

    private func linger(_ seconds: UInt32 = 2) {
        sleep(seconds)
    }

    func testScreenshots() throws {
        let app = launch(["-screenshots"])
        let row = app.descendants(matching: .any).matching(identifier: "libraryRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        sleep(1)
        snapshot(app, "01_library")

        press(row)
        XCTAssertTrue(app.buttons["shareArchive"].waitForExistence(timeout: 5))
        sleep(1)
        snapshot(app, "02_bundle")
        #if os(macOS)
            app.typeKey("n", modifierFlags: .command)
        #else
            navigateBack(app)
            tap(app.buttons["newBundle"])
        #endif
        XCTAssertTrue(app.buttons["kind-development"].waitForExistence(timeout: 5))
        sleep(1)
        snapshot(app, "03_signing_type")
        advance(app)

        tap(app.buttons["bundle-com.demo.fieldnotes"])
        advance(app)
        XCTAssertTrue(app.switches["capability-APP_GROUPS"].waitForExistence(timeout: 10))
        toggle(app, "capability-ICLOUD")
        toggle(app, "capability-PUSH_NOTIFICATIONS")
        #if os(iOS)
            for _ in 0..<8 { app.swipeDown(velocity: .fast) }
        #endif
        sleep(1)
        snapshot(app, "04_capabilities")
        advance(app)

        tap(app.buttons["selectAllDevices"])
        sleep(1)
        snapshot(app, "05_devices")
        advance(app)
        advance(app)
        tap(app.buttons["generate"])
        XCTAssertTrue(app.descendants(matching: .any)["generationSucceeded"].waitForExistence(timeout: 30))
        sleep(2)
        snapshot(app, "06_ready")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        #if os(macOS)
            let image = app.windows.firstMatch.screenshot()
        #else
            let image = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func advance(_ app: XCUIApplication) {
        let button = app.buttons["continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: button)
        waitForExpectations(timeout: 10)
        press(button)
    }

    private func type(_ text: String, into element: XCUIElement) {
        for _ in 0..<5 {
            press(element)
            if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            usleep(400_000)
        }
        element.typeText(text)
    }

    private func press(_ element: XCUIElement) {
        #if os(macOS)
            element.click()
        #else
            element.tap()
        #endif
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
        press(element)
    }

    private func toggle(_ app: XCUIApplication, _ identifier: String) {
        let element = app.switches[identifier]
        scrollTo(element, in: app)
        #if os(iOS)
            element.switches.firstMatch.exists ? element.switches.firstMatch.tap() : press(element)
        #else
            element.click()
        #endif
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        #if os(iOS)
            var attempts = 0
            while !(element.exists && element.isHittable) && attempts < 15 {
                app.swipeUp(velocity: .slow)
                attempts += 1
            }
        #endif
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
    }

    private func navigateBack(_ app: XCUIApplication) {
        #if os(iOS)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        #else
            app.typeKey("[", modifierFlags: .command)
        #endif
        sleep(1)
    }
}
