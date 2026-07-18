import XCTest

@MainActor
final class EmberFolioUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTurnsFromNowToTogether() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-FondDesignGallery",
            "-FondGalleryAppearance",
            "dark",
        ]
        app.launch()

        let nowFace = app.descendants(matching: .any)["fond.face.now"]
        let togetherFace = app.descendants(matching: .any)["fond.face.together"]
        XCTAssertTrue(nowFace.waitForExistence(timeout: 3))
        XCTAssertTrue(nowFace.isHittable)
        XCTAssertFalse(togetherFace.isHittable)

        app.otherElements["fond.card"].swipeLeft()

        expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: togetherFace
        )
        waitForExpectations(timeout: 2)
        XCTAssertFalse(nowFace.isHittable)
    }

    func testPrimaryTargetsExist() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-FondDesignGallery",
            "-FondGalleryAppearance",
            "light",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["fond.toolbar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["fond.compose"].exists)
        XCTAssertTrue(app.buttons["fond.send"].exists)
    }
}
