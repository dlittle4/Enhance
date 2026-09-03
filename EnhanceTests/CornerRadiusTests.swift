import Testing
import Foundation
@testable import Enhance

/// SQUARE CORNERS: every radius token goes to 0 under the flag and back when it is off.
@Suite(.serialized)
struct CornerRadiusTests {
    @Test func tokensCollapseToZeroUnderTheFlag() {
        let key = FeatureFlags.squareCornersKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(false, forKey: key)
        #expect(AppConstants.CornerRadius.standard == 8)
        #expect(AppConstants.CornerRadius.card == 16)
        #expect(AppConstants.CornerRadius.pill == 100)
        #expect(AppConstants.CornerRadius.resolve(19) == 19)

        UserDefaults.standard.set(true, forKey: key)
        let all: [CGFloat] = [AppConstants.CornerRadius.tiny, AppConstants.CornerRadius.chip,
                              AppConstants.CornerRadius.small, AppConstants.CornerRadius.standard,
                              AppConstants.CornerRadius.medium, AppConstants.CornerRadius.large,
                              AppConstants.CornerRadius.card, AppConstants.CornerRadius.control,
                              AppConstants.CornerRadius.circle, AppConstants.CornerRadius.pill,
                              AppConstants.CornerRadius.canvasOuter, AppConstants.CornerRadius.canvasInner,
                              AppConstants.CornerRadius.resolve(19)]
        for radius in all { #expect(radius == 0) }
    }
}
