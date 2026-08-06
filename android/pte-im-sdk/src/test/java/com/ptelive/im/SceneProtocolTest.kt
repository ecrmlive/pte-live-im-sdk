package com.ptelive.im

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** SDK-only protocol tests. They do not start the business Demo or call a UI layer. */
class SceneProtocolTest {
  @Test
  fun mapsEverySceneToItsWireGroup() {
    assertEquals("show:room-a", groupNameForScene(PteIMSceneKind.SHOW, "room-a"))
    assertEquals("voice:room-a", groupNameForScene(PteIMSceneKind.VOICE, "room-a"))
    assertEquals("live:42", groupNameForScene(PteIMSceneKind.SHOP, "42"))
    assertEquals("sports:sports-live-42", groupNameForScene(PteIMSceneKind.SPORTS, "sports-live-42"))
  }

  @Test
  fun rejectsInvalidSportsRoomButAcceptsOtherRooms() {
    assertSceneRoomId(PteIMSceneKind.SPORTS, "sports-live-42")
    assertSceneRoomId(PteIMSceneKind.SHOW, "show-e2e")
    assertThrows(IllegalArgumentException::class.java) {
      assertSceneRoomId(PteIMSceneKind.SPORTS, "show-e2e")
    }
  }

  @Test
  fun deduplicatesEventsAndDetectsRoomSequenceGap() {
    val tracker = RoomSeqTracker()
    val first = JSONObject().put("eventId", "evt-1").put("roomSeq", 1)
    val duplicate = JSONObject().put("eventId", "evt-1").put("roomSeq", 1)
    val gap = JSONObject().put("eventId", "evt-3").put("roomSeq", 3)

    assertTrue(tracker.accept(first))
    assertFalse(tracker.accept(duplicate))
    assertTrue(tracker.needsCatchUp(gap))
    assertEquals(1, tracker.getLastRoomSeq())
  }
}
