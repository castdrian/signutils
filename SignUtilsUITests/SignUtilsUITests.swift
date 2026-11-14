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
        app.buttons["addKey"].tap()
        XCTAssertTrue(app.textFields["keyID"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connect"].isEnabled)
    }

    func testCreatesAndRevokesASigningBundle() {
        let app = launch(["-demo"])
        let newBundle = app.buttons["newBundle"]
        XCTAssertTrue(newBundle.waitForExistence(timeout: 20))
        newBundle.tap()

        tap(app.buttons["kind-development"])
        advance(app)

        app.buttons["New"].firstMatch.tap()
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
        generate.tap()
        XCTAssertTrue(app.descendants(matching: .any)["generationSucceeded"].waitForExistence(timeout: 30))
        tap(app.buttons["finish"])

        let row = app.descendants(matching: .any).matching(identifier: "libraryRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["com.demo.uitest"].exists || row.label.contains("com.demo.uitest"))
        row.tap()

        let revoke = app.buttons["revokeAll"]
        scrollTo(revoke, in: app)
        revoke.tap()
        let confirm = app.buttons["Revoke"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Certificate revoked"].waitForExistence(timeout: 15))
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["revokeAll"])
        waitForExpectations(timeout: 15)
    }

    func testScreenshots() throws {
        let app = launch(["-screenshots"])
        let row = app.descendants(matching: .any).matching(identifier: "libraryRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        sleep(1)
        snapshot(app, "01_library")

        row.tap()
        XCTAssertTrue(app.buttons["shareArchive"].waitForExistence(timeout: 5))
        sleep(1)
        snapshot(app, "02_bundle")
        navigateBack(app)

        tap(app.buttons["newBundle"])
        XCTAssertTrue(app.buttons["kind-development"].waitForExistence(timeout: 5))
        sleep(1)
        snapshot(app, "03_signing_type")
        advance(app)

        tap(app.buttons["bundle-com.demo.feather"])
        advance(app)
        XCTAssertTrue(app.switches["capability-APP_GROUPS"].waitForExistence(timeout: 10))
        toggle(app, "capability-ICLOUD")
        toggle(app, "capability-PUSH_NOTIFICATIONS")
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
        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }

    private func advance(_ app: XCUIApplication) {
        let button = app.buttons["continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: button)
        waitForExpectations(timeout: 10)
        button.tap()
    }

    private func type(_ text: String, into element: XCUIElement) {
        for _ in 0..<5 {
            element.tap()
            if (element.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            usleep(400_000)
        }
        element.typeText(text)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
        element.tap()
    }

    private func toggle(_ app: XCUIApplication, _ identifier: String) {
        let element = app.switches[identifier]
        scrollTo(element, in: app)
        #if os(iOS)
            element.switches.firstMatch.exists ? element.switches.firstMatch.tap() : element.tap()
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
