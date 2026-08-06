import test from 'node:test'
import assert from 'node:assert/strict'
import { PteIMWebSDK } from '../src/chat/index.ts'
import { installBrowserTestEnvironment, SimulatedIMService } from './support.ts'

test('模拟用户可完整使用 Commerce 扩展，且请求复用当前 IM 身份', async () => {
  const service = new SimulatedIMService()
  installBrowserTestEnvironment(service)
  const client = new PteIMWebSDK({ apiUrl: 'https://api.test', wsUrl: 'wss://im.test/ws', commerceDomain: 'https://commerce.test', sdkAppId: '140001', identifier: '810001', userId: '810001', userSig: 'simulated-alice-sig', expireAt: 1_780_100_000 })
  const [capabilities, gifts, wallet, backpack, orders, giftOrder, backpackOrder, packet, packetDetail, claimed] = await Promise.all([
    client.commerce.capabilities(),
    client.commerce.gifts(),
    client.commerce.wallet(),
    client.commerce.backpack(),
    client.commerce.orders(),
    client.commerce.sendGift({ clientRequestId: 'gift-1', sku: 'rose', quantity: 1, targetUserId: 810002 }),
    client.commerce.useBackpack({ clientRequestId: 'backpack-1', sku: 'rose', quantity: 1, sceneType: 'show', roomId: 'show-100' }),
    client.commerce.createRedPacket({ clientRequestId: 'packet-1', roomId: 'show-100', totalAmount: 100, totalCount: 2 }),
    client.commerce.redPacket('rp-1'),
    client.commerce.claimRedPacket('rp-1'),
  ])
  assert.deepEqual(capabilities, { version: 1, currency: 'COIN', gifts: true, backpack: true, orders: true, redPackets: true })
  assert.equal(gifts[0]?.unitAmount, 10)
  assert.equal(wallet.balance, 900)
  assert.equal(backpack[0]?.expiresAt, 1_780_100_000)
  assert.equal(orders[0]?.orderId, 'order-1')
  assert.equal(giftOrder.orderId, 'order-gift-1')
  assert.equal(backpackOrder.resourceId, 'rose')
  assert.equal(packet.remainingAmount, 100)
  assert.equal(packetDetail.redPacket.remainingCount, 2)
  assert.equal(claimed.myClaim?.amount, 20)
  const commerceRequest = service.requests.find((request) => request.url.includes('/v1/commerce/gifts/send'))
  assert.equal(commerceRequest?.headers.get('Authorization'), 'Bearer simulated-alice-sig')
  assert.equal(commerceRequest?.headers.get('X-Pte-User-Id'), '810001')
})
