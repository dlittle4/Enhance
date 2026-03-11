import Testing
@testable import Enhance

struct EnhanceTests {
    
    @Test func appConstantsExist() async throws {
        #expect(AppConstants.Zoom.maxScale > 0)
    }
}
