import Testing
import CoreGraphics
@testable import Enhance

struct CameraZoomLadderTests {

    // MARK: - Virtual devices

    @Test func tripleCameraSwitchovers_produceThreeOpticalStops() {
        let options = CameraZoomLadder.make(switchOverFactors: [2, 6], maxZoomFactor: 16)

        #expect(options.map(\.label) == ["0.5X", "1X", "3X"])
        #expect(options.map(\.videoZoomFactor) == [1, 2, 6])
    }

    @Test func dualWideSwitchover_producesTwoStops() {
        let options = CameraZoomLadder.make(switchOverFactors: [2], maxZoomFactor: 16)

        #expect(options.map(\.label) == ["0.5X", "1X"])
        #expect(options.map(\.videoZoomFactor) == [1, 2])
    }

    @Test func switchoverBeyondCeiling_isDropped() {
        let options = CameraZoomLadder.make(switchOverFactors: [2, 6], maxZoomFactor: 5)

        #expect(options.map(\.label) == ["0.5X", "1X"])
    }

    @Test func unsortedSwitchovers_areSortedNotTrusted() {
        let options = CameraZoomLadder.make(switchOverFactors: [6, 2], maxZoomFactor: 16)

        #expect(options.map(\.videoZoomFactor) == [1, 2, 6])
    }

    // MARK: - Single-module devices

    @Test func noSwitchovers_offersDigitalTwoX() {
        let options = CameraZoomLadder.make(switchOverFactors: [], maxZoomFactor: 8)

        #expect(options.map(\.label) == ["1X", "2X"])
        #expect(options.map(\.videoZoomFactor) == [1, 2])
    }

    @Test func noSwitchovers_tightCeiling_isOneXOnly() {
        let options = CameraZoomLadder.make(switchOverFactors: [], maxZoomFactor: 1.5)

        #expect(options.map(\.label) == ["1X"])
    }

    // MARK: - Default stop

    @Test func defaultIndex_isTheOneXStop() {
        let virtual = CameraZoomLadder.make(switchOverFactors: [2, 6], maxZoomFactor: 16)
        let single = CameraZoomLadder.make(switchOverFactors: [], maxZoomFactor: 8)

        #expect(virtual[CameraZoomLadder.defaultIndex(in: virtual)].label == "1X")
        #expect(single[CameraZoomLadder.defaultIndex(in: single)].label == "1X")
        #expect(CameraZoomLadder.defaultIndex(in: virtual) == 1)
        #expect(CameraZoomLadder.defaultIndex(in: single) == 0)
    }

    // MARK: - Labels

    @Test func labels_stripTrailingZeros() {
        #expect(CameraZoomLadder.label(forDisplayFactor: 0.5) == "0.5X")
        #expect(CameraZoomLadder.label(forDisplayFactor: 1.0) == "1X")
        #expect(CameraZoomLadder.label(forDisplayFactor: 3.0) == "3X")
        #expect(CameraZoomLadder.label(forDisplayFactor: 2.5) == "2.5X")
    }

    @Test func labels_roundToOneDecimal() {
        // 13/4 switchover ratios exist in the wild (e.g. 6.5/2).
        #expect(CameraZoomLadder.label(forDisplayFactor: 3.25) == "3.3X")
    }
}
