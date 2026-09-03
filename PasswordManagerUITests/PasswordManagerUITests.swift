import XCTest

final class PasswordManagerUITests: XCTestCase {
    private let masterPassword = "ui test master password"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    #if os(iOS)
    @MainActor
    func testCreateGenerateEditBackgroundLockUnlockAndDelete() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PASSWORD_MANAGER_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Create Your Vault"].waitForExistence(timeout: 10))
        enter(masterPassword, in: app.secureTextFields["create-master-password"])
        enter(masterPassword, in: app.secureTextFields["create-master-password-confirmation"])
        let createButton = app.buttons["create-vault-button"]
        XCTAssertTrue(createButton.isEnabled)
        createButton.tap()

        XCTAssertTrue(app.navigationBars["Passwords"].waitForExistence(timeout: 10))
        app.buttons["add-credential-button"].tap()
        XCTAssertTrue(app.navigationBars["New Credential"].waitForExistence(timeout: 5))
        enter("Example Account", in: app.textFields["credential-name"])
        enter("demo@example.com", in: app.textFields["credential-username"])
        enter("example.com", in: app.textFields["credential-website"])

        app.buttons["generate-password-button"].tap()
        XCTAssertTrue(app.navigationBars["Strong Password"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["generated-password-value"].exists)
        app.buttons["use-generated-password-button"].tap()
        XCTAssertTrue(app.navigationBars["Edit Credential"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Example Account"].waitForExistence(timeout: 5))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "password-manager-credential-detail"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["edit-credential-button"].tap()
        let nameField = app.textFields["credential-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(" Updated")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Example Account Updated"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Vault Locked"].waitForExistence(timeout: 5))
        enter(masterPassword, in: app.secureTextFields["unlock-master-password"])
        app.buttons["unlock-vault-button"].tap()

        XCTAssertTrue(app.navigationBars["Example Account Updated"].waitForExistence(timeout: 10))
        app.buttons["delete-credential-button"].tap()
        let confirmDelete = app.buttons.matching(identifier: "confirm-delete-button").firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(app.staticTexts["No Credentials"].waitForExistence(timeout: 5))
    }
    #endif

    #if os(macOS)
    @MainActor
    func testMacOSCredentialDetailScreenshot() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PASSWORD_MANAGER_UI_TEST_RUN_ID"] = UUID().uuidString
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Create Your Vault"].waitForExistence(timeout: 10))
        enter(masterPassword, in: app.secureTextFields["create-master-password"])
        enter(masterPassword, in: app.secureTextFields["create-master-password-confirmation"])
        let createButton = app.buttons["create-vault-button"]
        XCTAssertTrue(createButton.isEnabled)
        createButton.tap()

        let biometricWarningButton = app.buttons["OK"].firstMatch
        if biometricWarningButton.waitForExistence(timeout: 2) {
            biometricWarningButton.tap()
        }

        XCTAssertTrue(app.staticTexts["No Credentials"].waitForExistence(timeout: 10))
        let addButton = app.buttons["add-credential-button"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.textFields["credential-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        enter("Example Account", in: nameField)
        enter("demo@example.com", in: app.textFields["credential-username"])
        enter("example.com", in: app.textFields["credential-website"])
        enter("correct horse battery staple", in: app.secureTextFields["credential-password"])
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Example Account"].waitForExistence(timeout: 5))

        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "password-manager-macos-credential-detail"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif

    @MainActor
    private func enter(_ value: String, in element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()
        element.typeText(value)
    }
}
