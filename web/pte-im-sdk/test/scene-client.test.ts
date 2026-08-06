import test from 'node:test'
import assert from 'node:assert/strict'
import { PteIMSceneClient } from '../src/scene/index.ts'
import { eventually, installBrowserTestEnvironment, SimulatedIMService } from './support.ts'

test('模拟用户可进入社交直播、语聊、电商、体育房间并消费实时事件', async () => {
  const service = new SimulatedIMService()
  installBrowserTestEnvironment(service)
  const client = new PteIMSceneClient({ wsUrl: 'wss://im.test/ws', sdkAppId: '140001', userId: '810001', userSig: 'simulated-room-sig' })
  const events: string[] = []
  client.addListener({ onEvent: (eventType) => events.push(eventType) })
  const source = { getCurrentRoomSeq: async () => 0, fetchEventsAfter: async () => ({ currentRoomSeq: 0, events: [] }) }
  const expected = [
    { scene: 'show' as const, roomId: 'show-100', groupName: 'show:show-100' },
    { scene: 'voice' as const, roomId: 'voice-100', groupName: 'voice:voice-100' },
    { scene: 'shop' as const, roomId: 'shop-100', groupName: 'live:shop-100', extend: '{"role":0}' },
    { scene: 'sports' as const, roomId: 'sports-live-100', groupName: 'sports:sports-live-100' },
  ]
  for (const options of expected) {
    const entered = await client.enter({ ...options, catchUp: source })
    assert.equal(entered.groupName, options.groupName)
    await client.leave()
  }
  await eventually(() => assert.deepEqual(events, ['scene.user.enter', 'scene.user.enter', 'shop.gift.sent', 'sports.chat.created']))
  assert.equal(client.getLastRoomSeq(), 1)
  client.disconnect()
})
