import XCTest

/// Tests UI utilisés par le workflow GitHub pour capturer des écrans
/// qu'on ne peut pas obtenir avec un simple `simctl` (menu ouvert, confirmation).
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
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
