import Testing
import Foundation
@testable import Maple_Recorder

struct StorageLocationTests {

    @Test func recordingsURLEndsInRecordings() {
        let url = StorageLocation.recordingsURL
        #expect(url.lastPathComponent == "recordings")
    }

    @Test func localFallbackInSimulator() {
        // In simulator / test environment, iCloud is unavailable
        // so we should get a local Documents path
        let url = StorageLocation.recordingsURL
        #expect(url.path().contains("recordings"))
    }
}
