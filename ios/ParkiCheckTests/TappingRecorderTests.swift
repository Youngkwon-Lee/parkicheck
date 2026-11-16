import XCTest
@testable import ParkiCheck

@MainActor
final class TappingRecorderTests: XCTestCase {
    func testLeavingDuringCountdownDiscardsTheRecording() async throws {
        let recorder = TappingRecorder()
        recorder.begin()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(recorder.phase, .countdown(3))

        recorder.cancelIfUnfinished()
        XCTAssertEqual(recorder.phase, .ready)

        // The cancelled timer must not advance the phase afterwards.
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(recorder.phase, .ready)
    }
}
