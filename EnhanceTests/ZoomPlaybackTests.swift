import Testing
import Foundation
@testable import Enhance

struct ZoomPlaybackTests {

    private let steps = Double(EffectParameter.sliderSteps)

    // MARK: - Range

    /// The slider's endpoints must be exactly the generator's clamps. Asserted against
    /// the same literals `GIFGenerator.prepareDrawingContext` uses, so if one moves and
    /// the other does not, this fails rather than silently producing a slider region
    /// that does nothing.
    @Test func speed_unitEndpointsMatchGeneratorClamps() {
        #expect(ZoomPlayback.speed(unit: 0) == 0.25)
        #expect(ZoomPlayback.speed(unit: 1) == 4.0)
        #expect(ZoomPlayback.minSpeed == 0.25)
        #expect(ZoomPlayback.maxSpeed == 4.0)
    }

    @Test func speed_oneXIsTheTrackMidpoint() {
        #expect(abs(ZoomPlayback.speed(unit: 0.5) - 1.0) < 1e-9)
    }

    @Test func pause_spansZeroToFive() {
        #expect(ZoomPlayback.pause(unit: 0) == 0)
        #expect(ZoomPlayback.pause(unit: 1) == 5.0)
    }

    @Test func units_clampOutOfRangeInput() {
        #expect(ZoomPlayback.speed(unit: -1) == ZoomPlayback.minSpeed)
        #expect(ZoomPlayback.speed(unit: 2) == ZoomPlayback.maxSpeed)
        #expect(ZoomPlayback.unit(speed: 100) == 1.0)
        #expect(ZoomPlayback.unit(pause: -3) == 0.0)
    }

    // MARK: - Defaults land on the lattice

    /// The load-bearing property of the geometric map. The slider quantises to 20 steps,
    /// so a default sitting *between* steps would snap the first time the knob is
    /// touched — silently changing a value the user never edited.
    @Test func speed_defaultLandsOnALatticeStep() {
        let unit = ZoomPlayback.unit(speed: ZoomPlayback.defaultSpeed)
        #expect(abs(unit - 5.0 / steps) < 1e-9, "0.5x should be step 5 of 20, got \(unit * steps)")
        #expect(abs(ParameterSliderRow.quantise(unit) - unit) < 1e-9, "default must survive quantise unchanged")
    }

    @Test func pause_defaultLandsOnALatticeStep() {
        let unit = ZoomPlayback.unit(pause: ZoomPlayback.defaultPause)
        #expect(abs(unit - 4.0 / steps) < 1e-9, "1s should be step 4 of 20, got \(unit * steps)")
    }

    /// The no-zoom default has to sit on a step for the same reason 1s does, or opening a
    /// no-zoom editor and touching PAUSE would jerk the value the user never set.
    @Test func noZoomPause_landsOnALatticeStep() {
        let unit = ZoomPlayback.unit(pause: ZoomPlayback.noZoomPause)
        #expect(abs(unit - 12.0 / steps) < 1e-9, "3s should be step 12 of 20, got \(unit * steps)")
    }

    // MARK: - Round trips

    @Test func speedUnit_roundTripsAtEveryLatticeStep() {
        for step in 0...EffectParameter.sliderSteps {
            let unit = Double(step) / steps
            let back = ZoomPlayback.unit(speed: ZoomPlayback.speed(unit: unit))
            #expect(abs(back - unit) < 1e-9, "step \(step) round-tripped to \(back * steps)")
        }
    }

    @Test func pauseUnit_roundTripsAtEveryLatticeStep() {
        for step in 0...EffectParameter.sliderSteps {
            let unit = Double(step) / steps
            let back = ZoomPlayback.unit(pause: ZoomPlayback.pause(unit: unit))
            #expect(abs(back - unit) < 1e-9, "step \(step) round-tripped to \(back * steps)")
        }
    }

    @Test func speed_isMonotonicInUnit() {
        var previous = ZoomPlayback.speed(unit: 0)
        for step in 1...EffectParameter.sliderSteps {
            let next = ZoomPlayback.speed(unit: Double(step) / steps)
            #expect(next > previous, "speed must increase with slider position")
            previous = next
        }
    }

    // MARK: - Display

    @Test func speedText_dropsTrailingZeros() {
        #expect(ZoomPlayback.speedText(0.25) == "0.25X")
        #expect(ZoomPlayback.speedText(0.5) == "0.5X")
        #expect(ZoomPlayback.speedText(1.0) == "1X")
        #expect(ZoomPlayback.speedText(1.5) == "1.5X")
        #expect(ZoomPlayback.speedText(4.0) == "4X")
    }

    @Test func pauseText_formatsWholeAndQuarterSeconds() {
        #expect(ZoomPlayback.pauseText(0) == "0S")
        #expect(ZoomPlayback.pauseText(1.0) == "1S")
        #expect(ZoomPlayback.pauseText(2.5) == "2.5S")
        #expect(ZoomPlayback.pauseText(5.0) == "5S")
    }

    /// The value is rendered inside a 34pt knob. A formatting change that produced
    /// something longer should fail here rather than truncate on device.
    @Test func labels_fitTheSliderKnob() {
        for step in 0...EffectParameter.sliderSteps {
            let unit = Double(step) / steps
            let speed = ZoomPlayback.speedText(ZoomPlayback.speed(unit: unit))
            let pause = ZoomPlayback.pauseText(ZoomPlayback.pause(unit: unit))
            #expect(speed.count <= 5, "speed label too long at step \(step): \(speed)")
            #expect(pause.count <= 5, "pause label too long at step \(step): \(pause)")
        }
    }

    // MARK: - Default comparison

    /// Without tolerance this is the bug where RESET never disappears: move the knob off
    /// the default and back, and the round-trip yields 0.5000000000000001.
    @Test func isDefaultSpeed_toleratesRoundTripNoise() {
        let roundTripped = ZoomPlayback.speed(unit: ZoomPlayback.unit(speed: ZoomPlayback.defaultSpeed))
        #expect(ZoomPlayback.isDefaultSpeed(roundTripped))
        #expect(ZoomPlayback.isDefaultPause(
            ZoomPlayback.pause(unit: ZoomPlayback.unit(pause: ZoomPlayback.defaultPause))
        ))
    }

    @Test func isDefaultSpeed_rejectsRealChanges() {
        #expect(!ZoomPlayback.isDefaultSpeed(1.0))
        #expect(!ZoomPlayback.isDefaultPause(2.0))
    }
}
