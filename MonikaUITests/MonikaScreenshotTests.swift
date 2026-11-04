import XCTest

/// Tests UI utilisés par le workflow GitHub pour capturer les écrans interactifs
/// en DemoMode (réglages, confirmation d'effacement, streaming, erreur, pièces jointes, dictée).
final class MonikaScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testConversationEtEffacement() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES"]
        app.launch()

        let settingsButton = app.buttons["headerSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15), "Bouton Reglages de l'en-tete introuvable")
        sleep(2)
        settingsButton.tap()

        let clearButton = app.buttons["clearHistorySettingsButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5), "Bouton Effacer l'historique introuvable")
        if !clearButton.isHittable {
            app.swipeUp()
            sleep(1)
        }
        sleep(1)
        attachScreenshot(named: "03-reglages-conversation")

        clearButton.tap()

        let cancelButton = app.buttons["Annuler"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Dialogue de confirmation introuvable")
        sleep(1)
        attachScreenshot(named: "04-confirmation-effacement")
    }

    @MainActor
    func testReglages() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES"]
        app.launch()

        let settingsButton = app.buttons["headerSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15), "Bouton Reglages de l'en-tete introuvable")
        sleep(2)
        settingsButton.tap()

        let saveButton = app.buttons["saveSettingsButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Ecran Reglages non affiche")

        let lightButton = app.buttons["appearanceLightButton"]
        XCTAssertTrue(lightButton.waitForExistence(timeout: 5), "Bouton Clair introuvable")
        lightButton.tap()
        sleep(2)
        attachScreenshot(named: "05-reglages-clair")

        let darkButton = app.buttons["appearanceDarkButton"]
        XCTAssertTrue(darkButton.waitForExistence(timeout: 5), "Bouton Sombre introuvable")
        darkButton.tap()
        sleep(2)
        attachScreenshot(named: "06-reglages-sombre")

        let systemButton = app.buttons["appearanceSystemButton"]
        if systemButton.exists {
            systemButton.tap()
        }
    }

    @MainActor
    func testMonikaEcrit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES", "-demoTyping"]
        app.launch()

        let indicator = app.descendants(matching: .any)["typingIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 10), "Indicateur Monika ecrit introuvable")

        let stopButton = app.buttons["stopGenerationButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Bouton stop introuvable")

        sleep(2)
        attachScreenshot(named: "07-monika-ecrit")
    }

    @MainActor
    func testErreurReseau() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES", "-demoError"]
        app.launch()

        let retryButton = app.buttons["retryButton"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 10), "Bouton Reessayer introuvable")

        sleep(2)
        attachScreenshot(named: "08-erreur-reseau")
    }

    @MainActor
    func testPieceJointe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES"]
        app.launch()

        let attachmentButton = app.buttons["attachmentMenuButton"]
        XCTAssertTrue(attachmentButton.waitForExistence(timeout: 15), "Bouton piece jointe introuvable")
        sleep(2)
        attachmentButton.tap()

        let photoItem = app.buttons["Photo"]
        XCTAssertTrue(photoItem.waitForExistence(timeout: 5), "Option Photo introuvable")

        let fileItem = app.buttons["Fichier"]
        XCTAssertTrue(fileItem.waitForExistence(timeout: 5), "Option Fichier introuvable")

        sleep(1)
        attachScreenshot(named: "09-piece-jointe")
    }

    @MainActor
    func testDictee() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-MonikaDemo", "YES", "-demoDictation"]
        app.launch()

        let dictationButton = app.buttons["dictationButton"]
        XCTAssertTrue(dictationButton.waitForExistence(timeout: 10), "Bouton dictee introuvable")

        let composer = app.descendants(matching: .any)["composerTextField"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "Champ de saisie introuvable")

        sleep(2)
        attachScreenshot(named: "10-dictee")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let cleanName = name.hasSuffix(".png") ? String(name.dropLast(4)) : name
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = cleanName
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
