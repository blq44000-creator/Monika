import XCTest

/// Tests UI utilisés par le workflow GitHub pour capturer des écrans
/// qu'on ne peut pas obtenir avec un simple `simctl` (menu ouvert, confirmation, réglages).
final class MonikaScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testMenuOuvert() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES"]
        app.launch()

        let menuButton = app.buttons["menuButton"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 15), "Bouton menu introuvable")
        sleep(2)
        menuButton.tap()

        let clearItem = app.buttons["Effacer l'historique"]
        XCTAssertTrue(clearItem.waitForExistence(timeout: 5), "Option « Effacer l'historique » introuvable")
        sleep(1)
        attachScreenshot(named: "03-menu-ouvert")

        clearItem.tap()
        sleep(1)
        attachScreenshot(named: "04-confirmation-effacement")
    }

    @MainActor
    func testReglages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES"]
        app.launch()

        let menuButton = app.buttons["menuButton"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 15), "Bouton menu introuvable")
        sleep(2)
        menuButton.tap()

        let settingsItem = app.buttons["Réglages"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 5), "Option « Réglages » introuvable")
        settingsItem.tap()

        let saveButton = app.buttons["saveSettingsButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Écran Réglages non affiché")

        // Capture en mode clair (en DemoMode : https://exemple.com + jeton masqué)
        let lightButton = app.buttons["appearanceLightButton"]
        XCTAssertTrue(lightButton.waitForExistence(timeout: 5), "Bouton Clair introuvable")
        lightButton.tap()
        sleep(2)
        attachScreenshot(named: "05-reglages-clair")

        // Capture en mode sombre
        let darkButton = app.buttons["appearanceDarkButton"]
        XCTAssertTrue(darkButton.waitForExistence(timeout: 5), "Bouton Sombre introuvable")
        darkButton.tap()
        sleep(2)
        attachScreenshot(named: "06-reglages-sombre")

        // Remet l'apparence sur Système
        let systemButton = app.buttons["appearanceSystemButton"]
        if systemButton.exists {
            systemButton.tap()
        }
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
