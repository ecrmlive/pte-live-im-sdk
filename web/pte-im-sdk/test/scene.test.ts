import test from 'node:test'
import assert from 'node:assert/strict'
import { RoomSeqTracker, eventTypeFromFrame, assertSceneRoomId, groupNameForScene } from '../src/scene/index.ts'

test('groupNameForScene', () => {
  assert.equal(groupNameForScene('shop', '123'), 'live:123')
  assert.equal(groupNameForScene('sports', 'sports-live-9'), 'sports:sports-live-9')
  assert.equal(groupNameForScene('show', 'abc'), 'show:abc')
  assert.equal(groupNameForScene('voice', 'abc'), 'voice:abc')
})

test('assertSceneRoomId sports', () => {
  assert.throws(() => assertSceneRoomId('sports', '123'), /sports-live/)
  assert.doesNotThrow(() => assertSceneRoomId('sports', 'sports-live-123'))
})

test('RoomSeqTracker accept and gap', () => {
  const tracker = new RoomSeqTracker(0)
  assert.equal(tracker.accept({ eventId: 'a', roomSeq: 1 }), true)
  assert.equal(tracker.accept({ eventId: 'a', roomSeq: 1 }), false)
  assert.equal(tracker.needsCatchUp({ roomSeq: 3 }), true)
  assert.equal(tracker.accept({ eventId: 'b', roomSeq: 2 }), true)
  assert.equal(tracker.getLastRoomSeq(), 2)
})

test('eventTypeFromFrame nested and flat', () => {
  const nested = eventTypeFromFrame({
    data: { event_type: 'shop.gift.sent', scene: { payload: { eventId: 'e1', roomSeq: 5 } } },
  })
  assert.equal(nested.eventType, 'shop.gift.sent')
  assert.equal(nested.payload?.roomSeq, 5)

  const flat = eventTypeFromFrame({
    msg: 'sports.chat.created',
    data: { eventId: 'e2', roomSeq: 9, text: 'hi' },
  })
  assert.equal(flat.eventType, 'sports.chat.created')
  assert.equal(flat.payload?.roomSeq, 9)
})
