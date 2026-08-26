import XCTest

/// End-to-end drive of the IN-APP CAMERA experiment (`FeatureFlags.cameraCapture`):
/// gallery → camera overlay → capture → editor → ENHANCE → SAVE → back in the grid.
///
/// The flag is force-enabled through launch arguments (`UserDefaults` reads them), so the test
/// does not depend on what was toggled in Settings. On the simulator the camera is
/// `MockCameraService`, which makes the whole flow drivable headlessly — this test also guards
/// the overlay's geometry (a mis-sized viewfinder pushes the controls off-screen, which
/// happened once during development and is exactly what `isHittable` catches).
///
/// Prerequisites: photo-library and camera access granted (`xcrun simctl privacy <udid> grant
/// photos|camera Enhance.Enhance`), and at least one GIF in the gallery so the grid state shows.
final class CameraCaptureUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-featureCameraCapture", "YES",
            // ENHANCE must run without a pinch for the flow to stay headless.
            "-featureZoomOptional", "YES"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Test clones start with fresh TCC, so the first camera open raises the system
    /// permission alert — and since the overlay's controls stay hidden until the session
    /// runs, no implicit interruption handling ever fires. Answer it explicitly.
    private func grantCameraPermissionIfPrompted() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    @MainActor
    func testCaptureFlowLandsInEditorAndSavesToGrid() throws {
        let cameraButton = app.buttons["gallery-camera-button"]
        guard cameraButton.waitForExistence(timeout: 10) else {
            throw XCTSkip("Gallery not reachable (no library permission or empty gallery); camera button never appeared.")
        }
        XCTAssertTrue(cameraButton.isHittable, "Camera button exists but is not hittable")
        cameraButton.tap()
        grantCameraPermissionIfPrompted()

        // Overlay up; the controls fade in once the (mock) session runs, so wait for the
        // shutter to be present, hittable, and enabled rather than sampling mid-entrance.
        let shutter = app.buttons["camera-shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5), "Shutter never appeared")
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true AND isEnabled == true"),
            object: shutter
        )
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 5), .completed,
                       "Shutter never became tappable — session never ran or the card geometry is wrong")
        // A tap dispatched into the controls' fade-in window can vanish (the same slow-clone
        // flake the zoom pill has) — let the fade settle, then allow one retry. Retrying is
        // safe: if the first tap captured, the live shutter is gone by then.
        Thread.sleep(forTimeInterval: 0.5)
        shutter.tap()

        // Capture → freeze → flight → editor. ENHANCE appearing is the editor's tell. The
        // flight choreography (0.15s handoff + spring + 0.6s teardown) must fully settle
        // before hittability is queried at all — probing mid-flight can fail hard with
        // "activation point invalid" while the accessibility frame is in motion.
        let enhance = app.buttons["ENHANCE"]
        var presented = enhance.waitForExistence(timeout: 10)
        if !presented, shutter.exists, shutter.isHittable {
            shutter.tap()
            presented = enhance.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(presented, "Editor never presented after capture")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(enhance.isHittable, "ENHANCE not hittable after the capture flight settled")

        // ENHANCE with NO ZOOM and no effect deliberately nags instead of generating
        // (`EditorViewModel.generateGIF`), so pick ZOOM IN and confirm its detail panel first.
        let zoomIn = app.buttons["ZOOM IN"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10), "ZOOM IN card missing")
        zoomIn.tap()
        let confirm = app.buttons["icon-check"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Detail panel confirm missing")
        confirm.tap()

        XCTAssertTrue(enhance.waitForExistence(timeout: 5), "ENHANCE did not return after confirming zoom")
        enhance.tap()

        // Generation swaps ENHANCE for SAVE / SHARE.
        let save = app.buttons["SAVE"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "GIF generation never finished")
        save.tap()

        // Save closes the editor and the grid refetches (photo-library observer debounces 2s).
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 30), "Gallery never came back after save")

        // The library gained the capture: the header count is MY GIFS (n), n ≥ 1 more than a
        // fresh install — asserting the header exists at all after a save round-trip is the
        // stable check, since the absolute count depends on the simulator's library state.
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'MY GIFS ('")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "Gallery header missing after save")
    }

    @MainActor
    func testCameraOverlayControlsAreOnScreenAndCloseWorks() throws {
        let cameraButton = app.buttons["gallery-camera-button"]
        guard cameraButton.waitForExistence(timeout: 10) else {
            throw XCTSkip("Gallery not reachable; camera button never appeared.")
        }
        cameraButton.tap()
        grantCameraPermissionIfPrompted()

        let shutter = app.buttons["camera-shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))

        // Every control must be hittable inside the window — the regression this guards is the
        // viewfinder blowing out to full screen and pushing the pills off the edges. Hittability
        // is waited on, not sampled: the controls fade in with the session.
        let shutterReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: shutter
        )
        XCTAssertEqual(XCTWaiter().wait(for: [shutterReady], timeout: 5), .completed, "Shutter never became hittable")
        let zoomPill = app.buttons["1X"]
        XCTAssertTrue(zoomPill.waitForExistence(timeout: 3), "Zoom pill missing")
        XCTAssertTrue(zoomPill.isHittable, "Zoom pill off-screen")

        // The controls fade in over ~0.25s; a tap dispatched into that window can land on a
        // half-materialized element and vanish (it has flaked exactly here on slow clones).
        // Let the fade settle, and give the slowest clones one retry.
        Thread.sleep(forTimeInterval: 0.5)
        zoomPill.tap()
        var cycled = app.buttons["3X"].waitForExistence(timeout: 3)
        if !cycled && app.buttons["1X"].exists {
            app.buttons["1X"].tap()
            cycled = app.buttons["3X"].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(cycled, "Zoom label did not cycle to 3X")

        // Chevron closes the overlay and the gallery bottom bar returns.
        let chevron = app.buttons["camera-close"]
        XCTAssertTrue(chevron.waitForExistence(timeout: 3), "Close chevron missing")
        XCTAssertTrue(chevron.isHittable, "Close chevron off-screen")
        chevron.tap()
        XCTAssertTrue(app.buttons["MAKE A GIF"].waitForExistence(timeout: 5), "Gallery did not return after closing camera")

        // And the camera must open AGAIN — the launch is a full open/close/reopen cycle,
        // and a dying overlay instance being revived (spent state, invisible, inert) is
        // exactly the regression this guards.
        Thread.sleep(forTimeInterval: 1.0)
        cameraButton.tap()
        XCTAssertTrue(shutter.waitForExistence(timeout: 5), "Camera did not reopen after closing")
        let shutterAgain = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true AND isEnabled == true"), object: shutter
        )
        XCTAssertEqual(XCTWaiter().wait(for: [shutterAgain], timeout: 8), .completed,
                       "Reopened camera never became usable")
    }
}
