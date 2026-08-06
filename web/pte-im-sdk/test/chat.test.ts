import test from 'node:test'
import assert from 'node:assert/strict'
import { PteIMWebSDK } from '../src/chat/index.ts'
import { eventually, installBrowserTestEnvironment, SimulatedIMService } from './support.ts'

test('两名模拟真实用户可完成 E2EE 聊天、ACK、关系与媒体流程', async () => {
  const service = new SimulatedIMService()
  installBrowserTestEnvironment(service)
  const base = { apiUrl: 'https://api.test', wsUrl: 'wss://im.test/ws', cosDomain: 'https://cos.test', sdkAppId: '140001', expireAt: 1_780_100_000 }
  const alice = new PteIMWebSDK({ ...base, identifier: '810001', userId: '810001', userSig: 'simulated-alice-sig' })
  const bob = new PteIMWebSDK({ ...base, identifier: '810002', userId: '810002', userSig: 'simulated-bob-sig' })
  const received: Array<{ text?: unknown; senderId: string }> = []
  const acknowledgements: string[] = []
  bob.addListener({ onMessage: (message) => received.push({ text: message.content.text, senderId: message.senderId }) })
  alice.addListener({ onSendAck: (ack) => acknowledgements.push(ack.serverMsgId) })

  await Promise.all([alice.start(), bob.start()])
  await eventually(() => assert.equal(alice.isConnected(), true))
  await eventually(() => assert.equal(bob.isConnected(), true))

  const conversation = await alice.openSingleConversation(810002)
  assert.deepEqual({ id: conversation.id, peerLastReadSeq: conversation.peerLastReadSeq }, { id: 101, peerLastReadSeq: 7 })
  const clientMsgId = await alice.sendText(conversation.id, '  你好，模拟用户乙  ')
  await eventually(() => assert.deepEqual(received, [{ text: '你好，模拟用户乙', senderId: '810001' }]))
  await eventually(() => assert.equal(acknowledgements.length, 1))
  assert.match(clientMsgId, /^[0-9a-f-]+$/)

  const [conversations, friends, follows, presence] = await Promise.all([
    alice.listConversations(), alice.listFriends(), alice.listFollows(), alice.queryPresence(['810002', 'invalid']),
  ])
  assert.equal(conversations.total, 1)
  assert.equal(friends.list[0]?.nickname, '模拟用户乙')
  assert.equal(follows.list[0]?.userId, '810002')
  assert.deepEqual(presence, { '810002': true })

  const uploaded = await alice.uploadMedia(new Blob(['图片数据'], { type: 'image/png' }))
  assert.deepEqual(uploaded, { key: 'chat/810001/photo.jpg', sizeBytes: 12, contentType: 'image/png' })
  assert.equal(alice.resolveMediaUrl(uploaded.key), 'https://cos.test/chat/810001/photo.jpg')
  alice.stop()
  bob.stop()
})
