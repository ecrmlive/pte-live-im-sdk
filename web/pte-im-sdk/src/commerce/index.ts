/**
 * Browser IM Commerce extension — same REST surface as Android/iOS/Harmony/UTS.
 * Shares chat UserSig; owns no WebSocket.
 */

export interface PteIMCommerceCapability {
  version: number
  currency: string
  gifts: boolean
  backpack: boolean
  orders: boolean
  redPackets: boolean
}

export interface PteIMGift {
  sku: string
  title: string
  coverUrl: string
  unitAmount: number
  currency: string
}

export interface PteIMWallet {
  balance: number
  currency: string
}

export interface PteIMBackpackItem {
  sku: string
  title: string
  coverUrl: string
  quantity: number
  expiresAt: number
}

export interface PteIMCommerceOrder {
  orderId: string
  type: string
  resourceId: string
  amount: number
  currency: string
  status: number
  snapshot: string
}

export interface PteIMRedPacket {
  redPacketId: string
  roomId: string
  mode: string
  greeting: string
  totalAmount: number
  totalCount: number
  remainingAmount: number
  remainingCount: number
  currency: string
  status: number
  expiresAt: number
}

export interface PteIMRedPacketDetail {
  redPacket: PteIMRedPacket
  myClaim?: { amount: number }
}

export interface PteIMGiftSendRequest {
  clientRequestId: string
  sku: string
  quantity: number
  targetUserId?: number
  sceneType?: string
  roomId?: string
}

export interface PteIMBackpackUseRequest {
  clientRequestId: string
  sku: string
  quantity: number
  sceneType?: string
  roomId?: string
}

export interface PteIMRedPacketCreateRequest {
  clientRequestId: string
  roomId: string
  totalAmount: number
  totalCount: number
  mode?: string
  greeting?: string
  sceneType?: string
  expiresIn?: number
}

type CommerceTransport = (path: string, body: Record<string, unknown>) => Promise<Record<string, unknown>>

export class PteIMCommerce {
  constructor(private readonly request: CommerceTransport) {}

  capabilities() {
    return this.request('/v1/commerce/capabilities', {}).then(toCapability)
  }

  gifts() {
    return this.request('/v1/commerce/gifts', {}).then((data) => listOf(data, toGift))
  }

  wallet() {
    return this.request('/v1/commerce/wallet', {}).then(toWallet)
  }

  backpack() {
    return this.request('/v1/commerce/backpack', {}).then((data) => listOf(data, toBackpack))
  }

  orders(limit = 50) {
    return this.request('/v1/commerce/orders', { limit }).then((data) => listOf(data, toOrder))
  }

  sendGift(request: PteIMGiftSendRequest) {
    return this.request('/v1/commerce/gifts/send', { ...request }).then(toOrder)
  }

  useBackpack(request: PteIMBackpackUseRequest) {
    return this.request('/v1/commerce/backpack/use', { ...request }).then(toOrder)
  }

  createRedPacket(request: PteIMRedPacketCreateRequest) {
    return this.request('/v1/commerce/red-packets/create', {
      mode: 'lucky',
      greeting: '',
      sceneType: 'live',
      expiresIn: 86400,
      ...request,
    }).then(toRedPacket)
  }

  redPacket(id: string) {
    return this.request(`/v1/commerce/red-packets/${id}`, {}).then(toRedPacketDetail)
  }

  claimRedPacket(id: string) {
    return this.request(`/v1/commerce/red-packets/${id}/claim`, {}).then(toRedPacketDetail)
  }
}

function listOf<T>(data: Record<string, unknown>, map: (row: Record<string, unknown>) => T): T[] {
  const raw = data.list ?? data.data
  if (!Array.isArray(raw)) return []
  return raw.map((item) => map((item || {}) as Record<string, unknown>))
}

function str(v: unknown) { return v == null ? '' : String(v) }
function num(v: unknown) { const n = Number(v); return Number.isFinite(n) ? n : 0 }
function bool(v: unknown) { return v === true || v === 'true' || v === 1 }

function toCapability(v: Record<string, unknown>): PteIMCommerceCapability {
  return {
    version: num(v.version) || 1,
    currency: str(v.currency) || 'COIN',
    gifts: bool(v.gifts),
    backpack: bool(v.backpack),
    orders: bool(v.orders),
    redPackets: bool(v.redPackets ?? v.red_packets),
  }
}

function toGift(v: Record<string, unknown>): PteIMGift {
  return {
    sku: str(v.sku),
    title: str(v.title),
    coverUrl: str(v.cover_url ?? v.coverUrl),
    unitAmount: num(v.unit_amount ?? v.unitAmount),
    currency: str(v.currency) || 'COIN',
  }
}

function toWallet(v: Record<string, unknown>): PteIMWallet {
  return { balance: num(v.balance), currency: str(v.currency) || 'COIN' }
}

function toBackpack(v: Record<string, unknown>): PteIMBackpackItem {
  return {
    sku: str(v.sku),
    title: str(v.title),
    coverUrl: str(v.cover_url ?? v.coverUrl),
    quantity: num(v.quantity),
    expiresAt: num(v.expires_at ?? v.expiresAt),
  }
}

function toOrder(v: Record<string, unknown>): PteIMCommerceOrder {
  return {
    orderId: str(v.order_id ?? v.orderId),
    type: str(v.type),
    resourceId: str(v.resource_id ?? v.resourceId),
    amount: num(v.amount),
    currency: str(v.currency) || 'COIN',
    status: num(v.status),
    snapshot: str(v.snapshot),
  }
}

function toRedPacket(v: Record<string, unknown>): PteIMRedPacket {
  return {
    redPacketId: str(v.red_packet_id ?? v.redPacketId),
    roomId: str(v.room_id ?? v.roomId),
    mode: str(v.mode),
    greeting: str(v.greeting),
    totalAmount: num(v.total_amount ?? v.totalAmount),
    totalCount: num(v.total_count ?? v.totalCount),
    remainingAmount: num(v.remaining_amount ?? v.remainingAmount),
    remainingCount: num(v.remaining_count ?? v.remainingCount),
    currency: str(v.currency) || 'COIN',
    status: num(v.status),
    expiresAt: num(v.expires_at ?? v.expiresAt),
  }
}

function toRedPacketDetail(v: Record<string, unknown>): PteIMRedPacketDetail {
  const packet = (v.redPacket || v.red_packet || v) as Record<string, unknown>
  const claimRaw = (v.myClaim || v.my_claim || v.claim) as Record<string, unknown> | undefined
  return {
    redPacket: toRedPacket(packet),
    myClaim: claimRaw ? { amount: num(claimRaw.amount) } : undefined,
  }
}
