import Testing
import CoreGraphics
@testable import Enhance

/// FEATURE-MOTION-EFFECTS.md §1c–1d: velocities from face centres and frame registration.
struct MotionTrackTests {

    @Test func aStillFaceHasNoVelocity() {
        let centres = Array(repeating: [CGPoint(x: 0.5, y: 0.5)], count: 6)
        let v = MotionTrack.subjectVelocities(faceCentres: centres)
        #expect(v.count == 6)
        #expect(v.allSatisfy { $0.motionMagnitude == 0 })
    }

    @Test func aDriftReadsAsSteadyRightwardMotion() {
        let centres = (0..<8).map { [CGPoint(x: 0.2 + 0.05 * CGFloat($0), y: 0.5)] }
        let v = MotionTrack.subjectVelocities(faceCentres: centres, smoothing: 1)
        for i in 1..<8 {
            #expect(abs(v[i].dx - 0.05) < 1e-9)
            #expect(abs(v[i].dy) < 1e-9)
        }
        #expect(v[0] == v[1], "frame 0 borrows the first step")
        #expect(abs(v[3].motionAngle) < 1e-9, "rightward is angle 0")
    }

    @Test func smoothingDampsAOneFrameDart() {
        var centres = Array(repeating: [CGPoint(x: 0.5, y: 0.5)], count: 6)
        centres[3] = [CGPoint(x: 0.7, y: 0.5)]  // one-frame jump and back
        let raw = MotionTrack.subjectVelocities(faceCentres: centres, smoothing: 1)
        let smooth = MotionTrack.subjectVelocities(faceCentres: centres, smoothing: 0.5)
        #expect(abs(raw[3].dx - 0.2) < 1e-9)
        #expect(smooth[3].dx < raw[3].dx)
        #expect(smooth[3].dx > 0)
    }

    @Test func nearestFaceIsFollowedAcrossFrames() {
        // Two faces; the tracked (largest, first-listed) one moves right, the other sits still.
        let centres: [[CGPoint]] = [
            [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.8, y: 0.5)],
            [CGPoint(x: 0.8, y: 0.5), CGPoint(x: 0.35, y: 0.5)],  // listed the other way round
            [CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.8, y: 0.5)],
        ]
        let v = MotionTrack.subjectVelocities(faceCentres: centres, smoothing: 1)
        #expect(abs(v[1].dx - 0.05) < 1e-9, "matched by nearest centre, not by list order")
        #expect(abs(v[2].dx - 0.05) < 1e-9)
    }

    @Test func aShortGapCarriesTheVelocityAndALongOneZeroesIt() {
        var centres = (0..<10).map { [CGPoint(x: 0.1 + 0.05 * CGFloat($0), y: 0.5)] }
        centres[4] = []
        centres[5] = []
        var long = centres
        long[6] = []; long[7] = []
        let short = MotionTrack.subjectVelocities(faceCentres: centres, smoothing: 1)
        #expect(short[5].dx > 0, "two missing frames keep the last velocity")
        let gapped = MotionTrack.subjectVelocities(faceCentres: long, smoothing: 1)
        #expect(gapped[7].motionMagnitude == 0, "past the maximum gap the track drops")
    }

    @Test func cameraVelocitiesSmoothTheRegistrationShifts() {
        let shifts = [CGVector.zero, CGVector(dx: 0.02, dy: 0), CGVector(dx: 0.02, dy: 0), CGVector(dx: -0.02, dy: 0)]
        let v = MotionTrack.cameraVelocities(translations: shifts, smoothing: 0.5)
        #expect(abs(v[1].dx - 0.01) < 1e-9)
        #expect(v[2].dx > v[1].dx)
        #expect(v[3].dx < v[2].dx)
        #expect(v[0] == v[1])
        #expect(MotionTrack.cameraVelocities(translations: []).isEmpty)
    }
}
