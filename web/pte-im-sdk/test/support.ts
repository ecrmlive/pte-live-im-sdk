import assert from 'node:assert/strict'

type SocketPeer = MockWebSocket

type Device = {
  userId: string
  deviceId: string
  publicKey: string
}

type RequestLog = {
  url: string
  headers: Headers
  body: Record<string, unknown>
}

/**
 * Web SDK tests run against this deterministic, in-process transport.
 * It models two separate demo accounts without using a real UserSig or network.
 */
export class SimulatedIMService {
  readonly devices = new Map<string, Device>()
  readonly sockets = new Map<string, Set<SocketPeer>>()
  readonly requests: RequestLog[] = []
  private readonly conversations = new Map<string, { id: number; users: string[] }>([
    ['101', { id: 101, users: ['810001', '810002'] }],
  ])

  attachSocket(socket: MockWebSocket, url: URL) {
    const userId = url.searchParams.get('identifier') || ''
    socket.userId = userId
    const set = this.sockets.get(userId) || new Set<SocketPeer>()
    set.add(socket)
    this.sockets.set(userId, set)
    queueMicrotask(() => {
      socket.open()
      // Chat ignores this frame; Scene waits for it as its WSS handshake marker.
      socket.receive({ code: 0, data: { connection_id: `scene-${userId}` } })
    })
  }

  detachSocket(socket: MockWebSocket) {
    this.sockets.get(socket.userId)?.delete(socket)
  }

  receiveSocket(socket: MockWebSocket, raw: string) {
    const frame = JSON.parse(raw) as Record<string, unknown>
    const action = String(frame.action || '')
    if (action === 'send_message') {
      const payload = frame.payload as Record<string, unknown>
      const conversationId = String(payload.conversationId)
      const conversation = this.conversations.get(conversationId)
      assert.ok(conversation, `unknown simulated conversation ${conversationId}`)
      const senderId = socket.userId
      const serverMsgId = `m-${payload.clientMsgId}`
      const message = {
        serverMsgId,
        clientMsgId: String(payload.clientMsgId),
        conversationId,
        senderId,
        type: String(payload.type),
        e2ee: payload.e2ee,
        createdAt: 1_780_000_000,
        serverSeq: 1,
      }
      for (const userId of conversation.users) {
        if (userId !== senderId) this.sockets.get(userId)?.forEach((peer) => peer.receive({ action: 'message', payload: message }))
      }
      socket.receive({ action: 'ack', payload: { clientMsgId: payload.clientMsgId, serverMsgId, serverSeq: 1 } })
      return
    }
    if (action === 'scene.enter') {
      const requestId = String(frame.request_id)
      const scene = String(frame.scene)
      const roomId = String(frame.room_id)
      socket.receive({
        msg: 'scene.enter',
        data: { type: 'scene.ack', ok: true, request_id: requestId, scene, room_id: roomId },
      })
      const eventType = scene === 'sports' ? 'sports.chat.created' : scene === 'shop' ? 'shop.gift.sent' : 'scene.user.enter'
      socket.receive({ msg: eventType, data: { eventId: `${scene}-${roomId}-1`, roomSeq: 1, actor: socket.userId } })
    }
  }

  async fetch(input: string | URL | Request, init?: RequestInit): Promise<Response> {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url)
    const headers = new Headers(init?.headers)
    let body: Record<string, unknown> = {}
    if (typeof init?.body === 'string') body = JSON.parse(init.body) as Record<string, unknown>
    this.requests.push({ url: url.toString(), headers, body })
    const userId = headers.get('X-Pte-User-Id') || ''

    if (url.hostname === 'commerce.test') return this.commerce(url.pathname, body)
    if (url.hostname === 'cos.test') return new Response('', { status: 200 })
    if (url.pathname === '/v1/im/media/put-url') return this.response(0, {
      key: 'chat/810001/photo.jpg', uploadUrl: 'https://cos.test/upload/photo.jpg', headers: { 'X-Cos-Token': 'demo' }, expiresAt: 1_780_000_100,
    })
    if (url.pathname === '/api/v1/chat/e2ee/device/register') {
      this.devices.set(String(body.device_id), { userId, deviceId: String(body.device_id), publicKey: String(body.public_key) })
      return this.response(1, { registered: true })
    }
    if (url.pathname === '/api/v1/chat/e2ee/device/list') {
      const conversation = this.conversations.get(String(body.conversation_id))
      const list = [...this.devices.values()].filter((device) => conversation?.users.includes(device.userId)).map((device) => ({
        user_id: Number(device.userId), device_id: device.deviceId, public_key: device.publicKey,
      }))
      return this.response(1, list)
    }
    if (url.pathname === '/api/v1/chat/e2ee/audit-key') return this.response(1, { enabled: false, required: false })
    if (url.pathname === '/v1/im/conversations/open-single') return this.response(1, {
      id: 101, type: 'single', title: '模拟用户乙', single_key: '810001:810002', last_message_seq: 0, last_message_at: 0, unread_count: 0,
      members: [{ user_id: Number(body.peerUserId), last_read_seq: 7 }],
    })
    if (url.pathname === '/v1/im/conversations') return this.response(1, { list: [{ id: 101, type: 'single', title: '模拟用户乙', unread_count: 0 }], total: 1 })
    if (url.pathname === '/v1/im/friends' || url.pathname === '/v1/im/follows') return this.response(1, { list: [{ userId: '810002', nickname: '模拟用户乙', gender: 'unknown' }], nextCursor: '', hasMore: false })
    if (url.pathname === '/v1/im/presence') return this.response(0, { list: [{ userId: '810002', online: true }] })
    return this.response(1, { ok: true })
  }

  private commerce(path: string, body: Record<string, unknown>) {
    if (path === '/v1/commerce/capabilities') return this.response(0, { version: 1, currency: 'COIN', gifts: true, backpack: true, orders: true, red_packets: true })
    if (path === '/v1/commerce/gifts') return this.response(0, { list: [{ sku: 'rose', title: '玫瑰', cover_url: 'gift/rose.png', unit_amount: 10, currency: 'COIN' }] })
    if (path === '/v1/commerce/wallet') return this.response(0, { balance: 900, currency: 'COIN' })
    if (path === '/v1/commerce/backpack') return this.response(0, { list: [{ sku: 'rose', title: '玫瑰', quantity: 2, expires_at: 1_780_100_000 }] })
    const order = { order_id: `order-${String(body.clientRequestId || '1')}`, type: 'gift', resource_id: String(body.sku || 'rose'), amount: 10, status: 1, snapshot: '{"title":"玫瑰"}' }
    if (path === '/v1/commerce/orders') return this.response(0, { list: [order] })
    if (path.endsWith('/send') || path.endsWith('/use')) return this.response(0, order)
    if (path === '/v1/commerce/red-packets/create') return this.response(0, this.redPacket({ remaining_amount: body.totalAmount, remaining_count: body.totalCount }))
    if (path.endsWith('/claim')) return this.response(0, { red_packet: this.redPacket({ remaining_amount: 80, remaining_count: 1 }), my_claim: { amount: 20 } })
    return this.response(0, { red_packet: this.redPacket({ remaining_amount: 100, remaining_count: 2 }) })
  }

  private redPacket(extra: Record<string, unknown>) {
    return { red_packet_id: 'rp-1', room_id: 'show-100', mode: 'lucky', greeting: '恭喜发财', total_amount: 100, total_count: 2, currency: 'COIN', status: 1, expires_at: 1_780_100_000, ...extra }
  }

  private response(code: number, data: unknown) {
    return new Response(JSON.stringify({ code, data }), { status: 200, headers: { 'Content-Type': 'application/json' } })
  }
}

export class MockWebSocket {
  static readonly CONNECTING = 0
  static readonly OPEN = 1
  static readonly CLOSING = 2
  static readonly CLOSED = 3
  readonly CONNECTING = MockWebSocket.CONNECTING
  readonly OPEN = MockWebSocket.OPEN
  readonly CLOSING = MockWebSocket.CLOSING
  readonly CLOSED = MockWebSocket.CLOSED
  readyState = MockWebSocket.CONNECTING
  onopen: ((event: Event) => void) | null = null
  onmessage: ((event: MessageEvent<string>) => void) | null = null
  onerror: ((event: Event) => void) | null = null
  onclose: ((event: CloseEvent) => void) | null = null
  userId = ''

  constructor(readonly url: string, private readonly service: SimulatedIMService) {
    service.attachSocket(this, new URL(url))
  }

  open() {
    if (this.readyState !== MockWebSocket.CONNECTING) return
    this.readyState = MockWebSocket.OPEN
    this.onopen?.(new Event('open'))
  }

  send(raw: string) { this.service.receiveSocket(this, raw) }

  receive(frame: Record<string, unknown>) {
    queueMicrotask(() => this.onmessage?.({ data: JSON.stringify(frame) } as MessageEvent<string>))
  }

  close() {
    if (this.readyState === MockWebSocket.CLOSED) return
    this.readyState = MockWebSocket.CLOSED
    this.service.detachSocket(this)
    queueMicrotask(() => this.onclose?.(new Event('close') as CloseEvent))
  }
}

export function installBrowserTestEnvironment(service: SimulatedIMService) {
  const target = globalThis as typeof globalThis & { window: typeof globalThis; localStorage: Storage; WebSocket: typeof WebSocket; fetch: typeof fetch }
  target.window = globalThis
  const values = new Map<string, string>()
  target.localStorage = {
    get length() { return values.size },
    clear: () => values.clear(),
    getItem: (key: string) => values.get(key) || null,
    key: (index: number) => [...values.keys()][index] || null,
    removeItem: (key: string) => values.delete(key),
    setItem: (key: string, value: string) => { values.set(key, String(value)) },
  } as Storage
  target.fetch = service.fetch.bind(service) as typeof fetch
  target.WebSocket = class extends MockWebSocket {
    constructor(url: string) { super(url, service) }
  } as unknown as typeof WebSocket
}

export async function eventually(assertion: () => void | Promise<void>, timeoutMs = 1_000) {
  const deadline = Date.now() + timeoutMs
  let lastError: unknown
  while (Date.now() < deadline) {
    try {
      await assertion()
      return
    } catch (error) {
      lastError = error
      await new Promise((resolve) => setTimeout(resolve, 5))
    }
  }
  throw lastError instanceof Error ? lastError : new Error('condition was not met')
}
