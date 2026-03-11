import XCTest

final class EnhanceUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Smoke Tests

    @MainActor
    func testAppLaunches() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testAppShowsGalleryOrNUX() throws {
        let nuxButton = app.buttons["CREATE YOUR FIRST GIF"]
        let galleryExists = app.collectionViews.firstMatch.waitForExistence(timeout: 5)
            || app.scrollViews.firstMatch.waitForExistence(timeout: 2)
        let nuxExists = nuxButton.waitForExistence(timeout: 5)

        XCTAssertTrue(galleryExists || nuxExists, "App should show either the GIF gallery or the new user experience")
    }

    @MainActor
    func testNUXButtonExists_whenNoGifs() throws {
        let nuxButton = app.buttons["CREATE YOUR FIRST GIF"]
        if nuxButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(nuxButton.isHittable)
        }
    }

    @MainActor
    func testGalleryViewToggle_existsWhenGifsPresent() throws {
        let gridButton = app.buttons["GRID"]
        let carouselButton = app.buttons["CAROUSEL"]

        if gridButton.waitForExistence(timeout: 5) {
            XCTAssertTrue(gridButton.exists)
            XCTAssertTrue(carouselButton.exists)

            carouselButton.tap()
            XCTAssertTrue(carouselButton.exists)

            gridButton.tap()
            XCTAssertTrue(gridButton.exists)
        }
    }

    // MARK: - Launch Screenshot

    @MainActor
    func testCaptureScreenshotOnLaunch() throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "App Launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
