import XCTest
@testable import PteIMSDK

final class SceneProtocolTests: XCTestCase {
  func testRoomSequenceRejectsDuplicatesAndDetectsGap() {
    let tracker = RoomSeqTracker()

    XCTAssertTrue(tracker.accept(["event_id": "evt-1", "room_seq": 1]))
    XCTAssertFalse(tracker.accept(["event_id": "evt-1", "room_seq": 1]))
    XCTAssertTrue(tracker.needsCatchUp(["event_id": "evt-3", "room_seq": 3]))
    XCTAssertTrue(tracker.accept(["event_id": "evt-3", "room_seq": 3]))
    XCTAssertFalse(tracker.accept(["event_id": "evt-2", "room_seq": 2]))
  }

  func testRoomSequenceAcceptsCamelCaseEnvelope() {
    let tracker = RoomSeqTracker()

    XCTAssertTrue(tracker.accept(["eventId": "evt-9", "roomSeq": 9]))
    XCTAssertFalse(tracker.accept(["eventId": "evt-9", "roomSeq": 9]))
  }
}
