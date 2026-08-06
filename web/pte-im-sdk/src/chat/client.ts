import { gcm } from '@noble/ciphers/aes.js'
import { p256 } from '@noble/curves/nist.js'
import { hmac } from '@noble/hashes/hmac.js'
import { sha256 } from '@noble/hashes/sha2.js'
import { PteIMCommerce } from '../commerce/index.ts'

export interface PteChatCredentials {
  provider?: string
  apiUrl: string
  wsUrl: string
  /** HTTPS origin used to resolve COS object keys for display (no trailing slash). */
  cosDomain?: string
  /** Optional IM Commerce HTTPS origin (no path). */
  commerceDomain?: string
  sdkAppId: string
  identifier: string
  userSig: string
  userId: string
  expireAt: number
}

export interface PteIMMessageReaction {
  emoji: string
  count: number
  reactedByMe: boolean
}

export interface PteIMBusinessContent {
  businessId: string
  title: string
  subtitle?: string
  actionUrl?: string
}

export interface PteMediaPutCredential {
  key: string
  uploadUrl: string
  headers: Record<string, string>
  expiresAt: number
}

export interface PteUploadedMedia {
  key: string
  sizeBytes: number
  contentType: string
}

export interface PteConversation {
  id: number
  type: 'single' | 'group' | string
  title: string
  avatar?: string
  /** C2C pair key `minUserId:maxUserId` when type is single. */
  singleKey?: string
  lastMessageSeq: number
  lastMessageSnapshot?: string
  lastMessageAt: number
  unreadCount: number
  /** Peer member last-read seq for C2C read receipts (when available). */
  peerLastReadSeq?: number
}

export interface PteContact {
  userId: string
  remark: string
  nickname: string
  avatar: string
  gender: 'unknown' | 'male' | 'female' | string
  followedAt: number
}

export interface PteGroupMember {
  userId: number
  role: number
  alias: string
  muteUntil: number
  joinedAt: number
}

export interface PteChatMessage {
  serverMsgId?: string
  clientMsgId: string
  conversationId: string
  senderId: string
  type: string
  content: Record<string, unknown>
  createdAt: number
  serverSeq?: number
  status?: number
  recalledAt?: number
  deletedAt?: number
  quoteMessageId?: string
  quoteSnapshot?: string
  reactions?: PteIMMessageReaction[]
  /** Client-only send pipeline state for optimistic UI. */
  sendState?: 'sending' | 'sent' | 'failed'
}

export interface PteSendAck {
  clientMsgId: string
  serverMsgId: string
  serverSeq: number
}

export interface PteChatListener {
  onConnectionChanged?: (connected: boolean) => void
  onMessage?: (message: PteChatMessage) => void
  /** Fired when the connection layer ACKs a local send_message (not a peer echo). */
  onSendAck?: (ack: PteSendAck) => void
  onMessageEvent?: (event: {
    eventType: string
    serverMsgId: string
    status?: number
    userId?: string
    emoji?: string
    reactionAction?: string
    recalledAt?: number
  }) => void
  onUserSigWillExpire?: () => void
  onUserSigExpired?: () => void
  onError?: (message: string) => void
}

type Identity = { privateKey: Uint8Array; deviceId: string }
type ResponseKey = { privateKey: Uint8Array; publicKey: string }
type E2EERequest = (path: string, body: Record<string, unknown>) => Promise<unknown>

/**
 * Web SDK implementation of the pte-live-im client protocol. It speaks only
 * the PTE UserSig, encrypted REST and PTE WebSocket contracts; no Qixi IM
 * transport or message storage is involved.
 */
/** @deprecated Prefer PteIMWebSDK alias; same chat client. */
export class PteLiveIMWebClient {
  private credentials: PteChatCredentials
  private socket: WebSocket | null = null
  private stopped = true
  private reconnectTimer: number | null = null
  private reconnectAttempt = 0
  private listeners = new Set<PteChatListener>()
  private readonly e2ee: E2EE
  readonly commerce: PteIMCommerce

  constructor(credentials: PteChatCredentials) {
    if (!credentials.apiUrl || !credentials.wsUrl || !credentials.sdkAppId || !credentials.identifier || !credentials.userSig) {
      throw new Error('PTE IM 凭证不完整')
    }
    this.credentials = { ...credentials }
    this.e2ee = new E2EE(
      this.scope(),
      Number(this.credentials.sdkAppId),
      Number(this.currentUserId()),
      (path, body) => this.request(path, body),
    )
    this.commerce = new PteIMCommerce((path, body) => this.commerceRequest(path, body))
  }

  /** Alias used by hosts aligning with native PteIMSDK naming. */
  static create(credentials: PteChatCredentials) {
    return new PteLiveIMWebClient(credentials)
  }

  addListener(listener: PteChatListener) {
    this.listeners.add(listener)
    // 页面后挂载 listener 时补发当前连接态，避免一直显示「正在连接」
    if (this.socket?.readyState === WebSocket.OPEN) {
      listener.onConnectionChanged?.(true)
    }
  }
  removeListener(listener: PteChatListener) { this.listeners.delete(listener) }
  currentUserId() { return this.credentials.userId || this.credentials.identifier }
  currentDeviceId() { return this.e2ee.deviceId() }
  isConnected() { return this.socket?.readyState === WebSocket.OPEN }

  async start() {
    this.stopped = false
    await this.e2ee.register()
    this.connect()
  }

  stop() {
    this.stopped = true
    if (this.reconnectTimer !== null) window.clearTimeout(this.reconnectTimer)
    this.reconnectTimer = null
    const socket = this.socket
    this.socket = null
    if (socket) socket.close()
    this.notifyConnection(false)
  }

  renewUserSig(credentials: Pick<PteChatCredentials, 'userSig' | 'expireAt'>) {
    if (!credentials.userSig) throw new Error('PTE IM UserSig 不能为空')
    this.credentials.userSig = credentials.userSig
    this.credentials.expireAt = credentials.expireAt
    this.sendEnvelope('renew_user_sig', { userSig: credentials.userSig })
  }

  async listConversations(page = 1, pageSize = 100): Promise<{ list: PteConversation[]; total: number }> {
    const data = await this.request('/v1/im/conversations', { page, pageSize }) as Record<string, unknown>
    const list = Array.isArray(data.list) ? data.list.map(toConversation) : []
    return { list, total: numberOf(data.total) }
  }

  async listFriends(cursor = '', limit = 100): Promise<{ list: PteContact[]; nextCursor: string; hasMore: boolean }> {
    const data = await this.request('/v1/im/friends', { cursor, limit }) as Record<string, unknown>
    return contactPage(data)
  }

  async listFollows(cursor = '', limit = 100): Promise<{ list: PteContact[]; nextCursor: string; hasMore: boolean }> {
    const data = await this.request('/v1/im/follows', { cursor, limit }) as Record<string, unknown>
    return contactPage(data)
  }

  follow(userId: number, remark = '') { return this.request('/v1/im/follows/follow', { targetUserId: userId, remark }) }
  unfollow(userId: number) { return this.request('/v1/im/follows/unfollow', { targetUserId: userId }) }
  block(userId: number) { return this.request('/v1/im/blocks/add', { targetUserId: userId }) }
  unblock(userId: number) { return this.request('/v1/im/blocks/remove', { targetUserId: userId }) }

  async listGroups(cursor = '', limit = 100): Promise<{ list: PteConversation[]; nextCursor: string; hasMore: boolean }> {
    const data = await this.request('/v1/im/groups', { cursor, limit }) as Record<string, unknown>
    return { list: Array.isArray(data.list) ? data.list.map(toConversation) : [], nextCursor: stringOf(data.nextCursor), hasMore: Boolean(data.hasMore) }
  }

  async groupMembers(conversationId: number, cursor = '', limit = 100): Promise<{ list: PteGroupMember[]; nextCursor: string; hasMore: boolean }> {
    const data = await this.request('/v1/im/groups/members', { conversationId, cursor, limit }) as Record<string, unknown>
    const list = Array.isArray(data.list) ? data.list.map((value) => {
      const item = value as Record<string, unknown>
      return { userId: numberOf(item.user_id), role: numberOf(item.role), alias: stringOf(item.alias), muteUntil: numberOf(item.mute_until), joinedAt: numberOf(item.joined_at) }
    }) : []
    return { list, nextCursor: stringOf(data.nextCursor), hasMore: Boolean(data.hasMore) }
  }

  joinGroup(conversationId: number) { return this.request('/v1/im/groups/join', { conversationId }) }
  leaveGroup(conversationId: number) { return this.request('/v1/im/groups/leave', { conversationId }) }
  inviteGroupMembers(conversationId: number, memberIds: number[]) { return this.request('/v1/im/groups/members/invite', { conversationId, memberIds }) }
  removeGroupMember(conversationId: number, memberId: number) { return this.request('/v1/im/groups/members/remove', { conversationId, memberId }) }

  async openSingleConversation(peerUserId: number): Promise<PteConversation> {
    const raw = await this.request('/v1/im/conversations/open-single', { peerUserId }) as Record<string, unknown>
    const conv = toConversation(raw)
    const members = Array.isArray(raw.members) ? raw.members : []
    const peer = members.find((item) => {
      const row = item as Record<string, unknown>
      return String(row.userId ?? row.user_id) === String(peerUserId)
    }) as Record<string, unknown> | undefined
    if (peer) {
      conv.peerLastReadSeq = numberOf(peer.lastReadSeq ?? peer.last_read_seq)
    }
    return conv
  }

  async createGroupConversation(title: string, memberIds: number[] = [], avatar = ''): Promise<PteConversation> {
    return toConversation(await this.request('/v1/im/conversations/create-group', { title, memberIds, avatar }) as Record<string, unknown>)
  }

  markConversationRead(conversationId: number, seq = 0) { return this.request('/v1/im/conversations/read', { conversationId, seq }) }
  recallMessage(messageId: string) { return this.request('/v1/im/messages/recall', { messageId }) }
  deleteMessage(messageId: string) { return this.request('/v1/im/messages/delete', { messageId }) }

  addReaction(messageId: string, emoji: string) {
    return this.request('/v1/im/messages/reactions/add', { messageId, emoji }) as Promise<{ messageId: string; reactions: PteIMMessageReaction[] }>
  }

  removeReaction(messageId: string, emoji: string) {
    return this.request('/v1/im/messages/reactions/remove', { messageId, emoji }) as Promise<{ messageId: string; reactions: PteIMMessageReaction[] }>
  }

  async ackMessages(conversationId: number, messageIds: string[], ackType: 'delivered' | 'read') {
    const ids = messageIds.map((value) => String(value || '').trim()).filter(Boolean)
    if (!ids.length) return
    const deviceId = await this.currentDeviceId()
    return this.request('/v1/im/messages/ack', { conversationId, messageIds: ids, ackType, deviceId })
  }

  /**
   * Page conversation history. The connection API returns newest-first; this
   * normalizes to oldest→newest so chat UIs can render top-to-bottom safely.
   */
  async history(conversationId: number, beforeSeq = 0, limit = 100): Promise<PteChatMessage[]> {
    const data = await this.request('/v1/im/conversations/messages', { conversationId, beforeSeq, limit }) as Record<string, unknown>
    const list = Array.isArray(data.list) ? data.list : []
    const messages = await Promise.all(list.map((item) => this.materializeMessage(item as Record<string, unknown>)))
    messages.sort((a, b) => {
      const seq = (a.serverSeq || 0) - (b.serverSeq || 0)
      if (seq !== 0) return seq
      return (a.createdAt || 0) - (b.createdAt || 0)
    })
    return messages
  }

  async sync(syncCursor = '', pageSize = 200): Promise<{ messages: PteChatMessage[]; nextCursor: string; hasMore: boolean }> {
    const data = await this.request('/v1/im/sync', { syncCursor, pageSize }) as Record<string, unknown>
    const list = Array.isArray(data.messages) ? data.messages : []
    return { messages: await Promise.all(list.map((item) => this.materializeMessage(item as Record<string, unknown>))), nextCursor: stringOf(data.nextCursor), hasMore: Boolean(data.hasMore) }
  }

  async sendText(conversationId: number | string, text: string, quoteMessageId?: string) {
    const normalized = text.trim()
    if (!normalized) throw new Error('消息不能为空')
    return this.sendMessage(conversationId, 'text', { text: normalized }, quoteMessageId)
  }

  async sendGift(conversationId: number | string, content: PteIMBusinessContent, quoteMessageId?: string) {
    return this.sendMessage(conversationId, 'gift', businessContent(content), quoteMessageId)
  }

  async sendRedPacket(conversationId: number | string, content: PteIMBusinessContent, quoteMessageId?: string) {
    return this.sendMessage(conversationId, 'red_packet', businessContent(content), quoteMessageId)
  }

  async sendOrder(conversationId: number | string, content: PteIMBusinessContent, quoteMessageId?: string) {
    return this.sendMessage(conversationId, 'order', businessContent(content), quoteMessageId)
  }

  async sendMessage(
    conversationId: number | string,
    type: string,
    content: Record<string, unknown>,
    quoteMessageId?: string,
  ): Promise<string> {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) throw new Error('PTE IM 连接中，请稍后再试')
    const clientMsgId = requestId()
    const e2ee = await this.e2ee.encrypt(Number(conversationId), content)
    const payload: Record<string, unknown> = { clientMsgId, conversationId: String(conversationId), type, e2ee }
    if (quoteMessageId) payload.quoteMessageId = String(quoteMessageId)
    this.sendEnvelope('send_message', payload)
    return clientMsgId
  }

  /**
   * Query peer online status via the IM connection layer.
   * Returns a map of userId → online. This is NOT the local socket state.
   */
  async queryPresence(userIds: Array<number | string>): Promise<Record<string, boolean>> {
    const ids = [...new Set(
      userIds
        .map((value) => Number(value))
        .filter((value) => Number.isSafeInteger(value) && value > 0),
    )]
    if (!ids.length) return {}
    const response = await fetch(`${this.credentials.apiUrl.replace(/\/$/, '')}/v1/im/presence`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.credentials.userSig}`,
        'X-Pte-Sdk-AppId': this.credentials.sdkAppId,
        'X-Pte-User-Id': this.currentUserId(),
      },
      body: JSON.stringify({ userIds: ids }),
    })
    const root = await response.json().catch(() => null) as Record<string, unknown> | null
    if (!root) throw new Error('PTE IM 在线状态响应无效')
    if (!response.ok || numberOf(root.code) !== 0) {
      throw new Error(stringOf(root.msg) || '查询在线状态失败')
    }
    const data = (root.data || {}) as Record<string, unknown>
    const list = Array.isArray(data.list) ? data.list : []
    const out: Record<string, boolean> = {}
    for (const item of list) {
      const row = (item || {}) as Record<string, unknown>
      const userId = stringOf(row.userId)
      if (!userId) continue
      out[userId] = Boolean(row.online)
    }
    return out
  }

  /**
   * Ask IM for a short-lived COS PUT URL, upload bytes directly to Tencent COS,
   * then return the object key. Message content must store `key`, not uploadUrl.
   */
  async uploadMedia(file: Blob, mediaType: 'image' | 'video' | 'voice' | 'file' = 'image'): Promise<PteUploadedMedia> {
    const contentType = normalizeMediaContentType(file, mediaType)
    const contentLength = file.size
    if (contentLength <= 0) throw new Error('文件不能为空')
    const credential = await this.requestMediaPutUrl({ mediaType, contentType, contentLength })
    const headers = new Headers()
    Object.entries(credential.headers || {}).forEach(([key, value]) => {
      if (value) headers.set(key, value)
    })
    if (!headers.has('Content-Type')) headers.set('Content-Type', contentType)
    const uploaded = await fetch(credential.uploadUrl, { method: 'PUT', headers, body: file })
    if (!uploaded.ok) throw new Error(`COS 上传失败（HTTP ${uploaded.status}）`)
    return { key: credential.key, sizeBytes: contentLength, contentType }
  }

  resolveMediaUrl(keyOrUrl: string): string {
    const value = String(keyOrUrl || '').trim()
    if (!value) return ''
    if (/^https?:\/\//i.test(value)) return value
    const base = String(this.credentials.cosDomain || '').replace(/\/$/, '')
    if (!base) return value
    return `${base}/${value.replace(/^\//, '')}`
  }

  /** Stable per account; do not include fluctuating URL punctuation or it regenerates device_id. */
  private scope() {
    const api = String(this.credentials.apiUrl || '').trim().replace(/\/+$/, '')
    const ws = String(this.credentials.wsUrl || '').trim().replace(/\/+$/, '')
    return `${api}|${ws}|${this.credentials.sdkAppId}|${this.currentUserId()}`
  }

  private async requestMediaPutUrl(body: {
    mediaType: string
    contentType: string
    contentLength: number
  }): Promise<PteMediaPutCredential> {
    // put-url is served by im-wss (proxied on api-im host) and returns plain {code:0,data}.
    const response = await fetch(`${this.credentials.apiUrl.replace(/\/$/, '')}/v1/im/media/put-url`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.credentials.userSig}`,
        'X-Pte-Sdk-AppId': this.credentials.sdkAppId,
        'X-Pte-User-Id': this.currentUserId(),
      },
      body: JSON.stringify(body),
    })
    const root = await response.json().catch(() => null) as Record<string, unknown> | null
    if (!root) throw new Error('PTE IM 上传凭证响应无效')
    if (!response.ok || numberOf(root.code) !== 0) {
      throw new Error(stringOf(root.msg) || '获取 COS 上传凭证失败')
    }
    const data = (root.data || {}) as Record<string, unknown>
    const key = stringOf(data.key)
    const uploadUrl = stringOf(data.uploadUrl)
    if (!key || !uploadUrl) throw new Error('COS 上传凭证不完整')
    const headersRaw = (data.headers || {}) as Record<string, unknown>
    const headers: Record<string, string> = {}
    Object.entries(headersRaw).forEach(([name, value]) => {
      if (value != null && value !== '') headers[name] = String(value)
    })
    return { key, uploadUrl, headers, expiresAt: numberOf(data.expiresAt) }
  }

  private async request(path: string, body: Record<string, unknown>): Promise<unknown> {
    const responseKey = await createResponseKey()
    const response = await fetch(`${this.credentials.apiUrl.replace(/\/$/, '')}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.credentials.userSig}`,
        'X-Pte-Sdk-AppId': this.credentials.sdkAppId,
        'X-Pte-User-Id': this.currentUserId(),
        'X-Pte-Response-Public-Key': responseKey.publicKey,
      },
      body: JSON.stringify(body),
    })
    const root = await response.json().catch(() => null) as Record<string, unknown> | null
    if (!root) throw new Error('PTE IM 响应无效')
    const envelope = root.version === 1 && root.algorithm === 'P-256/A256GCM'
    const decoded = envelope ? decryptResponse(root, responseKey) : root
    if (!response.ok || numberOf(decoded.code) !== 1) throw new Error(stringOf(decoded.msg) || 'PTE IM 请求失败')
    return decoded.data
  }

  private connect() {
    if (this.stopped || this.socket) return
    const url = new URL(this.credentials.wsUrl)
    url.searchParams.set('sdkAppID', this.credentials.sdkAppId)
    url.searchParams.set('identifier', this.credentials.identifier)
    url.searchParams.set('userSig', this.credentials.userSig)
    const socket = new WebSocket(url.toString())
    this.socket = socket
    socket.onopen = () => {
      if (this.socket !== socket || this.stopped) return
      this.reconnectAttempt = 0
      this.notifyConnection(true)
      this.sendEnvelope('login', {})
    }
    socket.onmessage = (event) => { void this.handleFrame(event.data) }
    socket.onerror = () => this.emitError('PTE IM 连接异常')
    socket.onclose = () => {
      if (this.socket !== socket) return
      this.socket = null
      this.notifyConnection(false)
      this.scheduleReconnect()
    }
  }

  private async handleFrame(raw: unknown) {
    try {
      const frame = JSON.parse(String(raw)) as Record<string, unknown>
      const action = stringOf(frame.action)
      if (action === 'message') {
        const message = await this.materializeMessage(frame.payload as Record<string, unknown>)
        this.listeners.forEach((listener) => listener.onMessage?.(message))
        if (message.serverMsgId) this.sendEnvelope('ack', { serverMsgId: message.serverMsgId })
      } else if (action === 'ack') {
        const payload = (frame.payload || {}) as Record<string, unknown>
        const clientMsgId = stringOf(payload.clientMsgId)
        const serverMsgId = stringOf(payload.serverMsgId)
        if (clientMsgId && serverMsgId) {
          const ack = {
            clientMsgId,
            serverMsgId,
            serverSeq: numberOf(payload.serverSeq),
          }
          this.listeners.forEach((listener) => listener.onSendAck?.(ack))
        }
      } else if (action === 'message_event') {
        const payload = frame.payload as Record<string, unknown>
        this.listeners.forEach((listener) => listener.onMessageEvent?.({
          eventType: stringOf(payload.eventType),
          serverMsgId: stringOf(payload.serverMsgId),
          status: numberOf(payload.status) || undefined,
          userId: stringOf(payload.userId) || undefined,
          emoji: stringOf(payload.emoji) || undefined,
          reactionAction: stringOf(payload.reactionAction) || undefined,
          recalledAt: numberOf(payload.recalledAt) || undefined,
        }))
      } else if (action === 'user_sig_will_expire') {
        this.listeners.forEach((listener) => listener.onUserSigWillExpire?.())
      } else if (action === 'user_sig_expired') {
        this.listeners.forEach((listener) => listener.onUserSigExpired?.())
      } else if (action === 'error') {
        const payload = frame.payload as Record<string, unknown>
        this.emitError(stringOf(payload.message) || 'PTE IM 操作失败')
      }
    } catch (error) {
      this.emitError(error instanceof Error ? error.message : 'PTE IM 消息解析失败')
    }
  }

  private async materializeMessage(raw: Record<string, unknown>): Promise<PteChatMessage> {
    const e2ee = raw.e2ee as Record<string, unknown> | undefined
    let type = stringOf(raw.type || raw.msg_type)
    let content: Record<string, unknown>
    if (e2ee) {
      try {
        content = await this.e2ee.decrypt(e2ee)
      } catch {
        // New/cleared browser identity is a different device_id; older envelopes
        // never wrapped the content key for it. Surface a placeholder instead of
        // failing the whole history/WS frame.
        type = 'text'
        content = { text: '无法在此设备查看', decryptFailed: true }
      }
    } else {
      content = (raw.content as Record<string, unknown>) || {}
    }
    for (const field of ['url', 'thumbnailUrl', 'coverUrl'] as const) {
      if (content[field]) content[field] = this.resolveMediaUrl(String(content[field]))
    }
    return {
      serverMsgId: stringOf(raw.serverMsgId || raw.message_id), clientMsgId: stringOf(raw.clientMsgId || raw.client_msg_id),
      conversationId: stringOf(raw.conversationId || raw.conversation_id), senderId: stringOf(raw.senderId || raw.sender_id),
      type, content, createdAt: numberOf(raw.createdAt || raw.sent_at || raw.sentAt) * (numberOf(raw.createdAt || raw.sent_at || raw.sentAt) < 10_000_000_000 ? 1000 : 1),
      serverSeq: numberOf(raw.serverSeq || raw.seq || raw.Seq), status: numberOf(raw.status), recalledAt: numberOf(raw.recalledAt || raw.recalled_at), deletedAt: numberOf(raw.deletedAt || raw.deleted_at),
      quoteMessageId: stringOf(raw.quoteMessageId || raw.quote_message_id) || undefined,
      quoteSnapshot: stringOf(raw.quoteSnapshot || raw.quote_snapshot) || undefined,
      reactions: parseReactions(raw.reactions),
    }
  }

  private async commerceRequest(path: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
    const domain = String(this.credentials.commerceDomain || '').replace(/\/$/, '')
    if (!domain) throw new Error('commerceDomain is not configured')
    const response = await fetch(`${domain}${path.startsWith('/') ? path : `/${path}`}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.credentials.userSig}`,
        'X-Pte-Sdk-AppId': this.credentials.sdkAppId,
        'X-Pte-User-Id': this.currentUserId(),
      },
      body: JSON.stringify(body),
    })
    const root = await response.json().catch(() => null) as Record<string, unknown> | null
    if (!root) throw new Error('PTE Commerce 响应无效')
    const code = numberOf(root.code)
    if (!response.ok || (code !== 0 && code !== 1)) throw new Error(stringOf(root.msg) || 'PTE Commerce 请求失败')
    return (root.data || root) as Record<string, unknown>
  }

  private sendEnvelope(action: string, payload: Record<string, unknown>) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return
    this.socket.send(JSON.stringify({ protocolVersion: 1, action, requestId: requestId(), sdkAppId: this.credentials.sdkAppId, userId: this.currentUserId(), userSig: this.credentials.userSig, payload }))
  }

  private scheduleReconnect() {
    if (this.stopped || this.reconnectTimer !== null) return
    const delay = Math.min(1000 * 2 ** Math.min(this.reconnectAttempt, 5), 30000)
    this.reconnectAttempt += 1
    this.reconnectTimer = window.setTimeout(() => { this.reconnectTimer = null; this.connect() }, delay)
  }

  private notifyConnection(connected: boolean) { this.listeners.forEach((listener) => listener.onConnectionChanged?.(connected)) }
  private emitError(message: string) { this.listeners.forEach((listener) => listener.onError?.(message)) }
}

class E2EE {
  private identityValue: Identity | null = null
  private readonly store: SecureStore

  constructor(
    private readonly scope: string,
    private readonly appId: number,
    private readonly userId: number,
    private readonly request: E2EERequest,
  ) {
    this.store = new SecureStore(`pte-live-im:${scope}`)
  }

  async register() {
    const identity = await this.identity()
    await this.request('/api/v1/chat/e2ee/device/register', {
      app_id: this.appId,
      user_id: this.userId,
      device_id: identity.deviceId,
      public_key: base64Url(p256.getPublicKey(identity.privateKey, false)),
      algorithm: 'P-256/A256GCM',
    })
  }

  async deviceId() { return (await this.identity()).deviceId }

  async encrypt(conversationId: number, content: Record<string, unknown>) {
    const recipients = await this.request('/api/v1/chat/e2ee/device/list', {
      app_id: this.appId,
      user_id: this.userId,
      conversation_id: conversationId,
    })
    const audit = await this.request('/api/v1/chat/e2ee/audit-key', {}) as Record<string, unknown>
    if (!Array.isArray(recipients)) throw new Error('PTE IM 加密收件人无效')
    const contentKey = crypto.getRandomValues(new Uint8Array(32))
    const nonce = crypto.getRandomValues(new Uint8Array(12))
    const ciphertext = gcm(contentKey, nonce, utf8('pte-live-im-message-v1')).encrypt(utf8(JSON.stringify(content)))
    const envelope: Record<string, unknown> = { version: 1, algorithm: 'P-256/A256GCM', ciphertext: base64Url(ciphertext), nonce: base64Url(nonce), recipients: recipients.map((value) => {
      const device = value as Record<string, unknown>
      const publicKey = stringOf(device.public_key ?? device.publicKey)
      const deviceId = stringOf(device.device_id ?? device.deviceId)
      const userId = numberOf(device.user_id ?? device.userId)
      if (!publicKey || !deviceId) throw new Error('PTE IM 加密收件人公钥无效')
      const wrapped = wrapKey(contentKey, publicKey)
      return { user_id: userId, device_id: deviceId, ephemeral_public_key: wrapped.publicKey, wrapped_key: wrapped.ciphertext, nonce: wrapped.nonce }
    }) }
    if (audit.enabled === true) {
      const wrapped = wrapKey(contentKey, stringOf(audit.public_key ?? audit.publicKey))
      envelope.audit_recipients = [{ key_id: stringOf(audit.key_id ?? audit.keyId), ephemeral_public_key: wrapped.publicKey, wrapped_key: wrapped.ciphertext, nonce: wrapped.nonce }]
    } else if (audit.required === true) {
      throw new Error('PTE IM 审计加密密钥不可用')
    }
    return envelope
  }

  async decrypt(envelope: Record<string, unknown>): Promise<Record<string, unknown>> {
    if (numberOf(envelope.version) !== 1 || envelope.algorithm !== 'P-256/A256GCM' || !Array.isArray(envelope.recipients)) throw new Error('PTE IM 加密消息格式无效')
    const identity = await this.identity()
    const recipient = (envelope.recipients as unknown[]).map((item) => item as Record<string, unknown>).find((item) => stringOf(item.device_id ?? item.deviceId) === identity.deviceId)
    if (!recipient) throw new Error('当前设备无法解密此消息')
    const nonce = decodeBase64Url(stringOf(recipient.nonce))
    const shared = sharedSecret(identity.privateKey, decodeBase64Url(stringOf(recipient.ephemeral_public_key ?? recipient.ephemeralPublicKey)))
    const key = gcm(deriveKey(shared, nonce, 'pte-live-im-audit-wrap-v1'), nonce, utf8('pte-live-im-audit-wrap-v1')).decrypt(decodeBase64Url(stringOf(recipient.wrapped_key ?? recipient.wrappedKey)))
    const messageNonce = decodeBase64Url(stringOf(envelope.nonce))
    return JSON.parse(utf8Decode(gcm(key, messageNonce, utf8('pte-live-im-message-v1')).decrypt(decodeBase64Url(stringOf(envelope.ciphertext))))) as Record<string, unknown>
  }

  private async identity(): Promise<Identity> {
    if (this.identityValue) return this.identityValue
    const saved = await this.store.get<{ privateKey: string; deviceId: string }>('identity')
    if (saved?.privateKey && saved.deviceId) {
      this.identityValue = { privateKey: decodeBase64Url(saved.privateKey), deviceId: saved.deviceId }
      return this.identityValue
    }
    this.identityValue = { privateKey: p256.utils.randomSecretKey(), deviceId: crypto.randomUUID() }
    const payload = { privateKey: base64Url(this.identityValue.privateKey), deviceId: this.identityValue.deviceId }
    await this.store.set('identity', payload)
    // Must survive reload; otherwise every H5 open is a new device and history never decrypts.
    const roundtrip = await this.store.get<{ privateKey: string; deviceId: string }>('identity')
    if (!roundtrip?.privateKey || roundtrip.deviceId !== payload.deviceId) {
      throw new Error('PTE IM 设备密钥无法持久化，请关闭无痕模式后重试')
    }
    return this.identityValue
  }
}

/**
 * Persist E2EE device identity. IndexedDB + non-extractable CryptoKey is preferred,
 * but mobile Safari / WeChat WebView often fail to restore CryptoKey — dual-write a
 * localStorage fallback so H5 keeps a stable device_id across reloads.
 */
class SecureStore {
  constructor(private readonly namespace: string) {}

  private lsKey(key: string) {
    return `pte-live-im-ls:${this.namespace}:${key}`
  }

  async get<T>(key: string): Promise<T | null> {
    try {
      const db = await openStore()
      const record = await idbGet<{ iv: ArrayBuffer | Uint8Array; ciphertext: ArrayBuffer | Uint8Array; keyRaw?: string }>(db, 'values', `${this.namespace}:${key}`)
      if (record?.keyRaw && record.iv && record.ciphertext) {
        const cryptoKey = await crypto.subtle.importKey('raw', decodeBase64Url(record.keyRaw), { name: 'AES-GCM' }, false, ['encrypt', 'decrypt'])
        const iv = record.iv instanceof Uint8Array ? record.iv : new Uint8Array(record.iv)
        const cipher = record.ciphertext instanceof Uint8Array ? record.ciphertext : new Uint8Array(record.ciphertext)
        const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, cryptoKey, cipher)
        return JSON.parse(new TextDecoder().decode(plain)) as T
      }
      const cryptoKey = await this.key(db)
      if (record && cryptoKey && record.iv && record.ciphertext) {
        const iv = record.iv instanceof Uint8Array ? record.iv : new Uint8Array(record.iv)
        const cipher = record.ciphertext instanceof Uint8Array ? record.ciphertext : new Uint8Array(record.ciphertext)
        const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, cryptoKey, cipher)
        return JSON.parse(new TextDecoder().decode(plain)) as T
      }
    } catch { /* fall through */ }
    try {
      if (typeof localStorage === 'undefined') return null
      const raw = localStorage.getItem(this.lsKey(key))
      if (!raw) return null
      return JSON.parse(raw) as T
    } catch { return null }
  }

  async set(key: string, value: unknown) {
    const json = JSON.stringify(value)
    try {
      if (typeof localStorage !== 'undefined') localStorage.setItem(this.lsKey(key), json)
    } catch { /* quota / private mode */ }
    try {
      const db = await openStore()
      const rawKey = crypto.getRandomValues(new Uint8Array(32))
      const cryptoKey = await crypto.subtle.importKey('raw', rawKey, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt'])
      const iv = crypto.getRandomValues(new Uint8Array(12))
      const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, cryptoKey, utf8(json))
      // Store AES raw alongside ciphertext — avoids non-extractable CryptoKey IDB restore bugs on mobile WebKit.
      await idbPut(db, 'values', { iv: iv.buffer, ciphertext, keyRaw: base64Url(rawKey) }, `${this.namespace}:${key}`)
    } catch { /* Browser privacy mode can disable IndexedDB; localStorage fallback remains. */ }
  }

  private async key(db: IDBDatabase): Promise<CryptoKey | null> {
    const id = `${this.namespace}:key`
    const existing = await idbGet<CryptoKey>(db, 'keys', id)
    if (existing && typeof (existing as CryptoKey).algorithm === 'object') return existing
    try {
      const created = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt'])
      await idbPut(db, 'keys', created, id)
      return created
    } catch { return null }
  }
}

let storePromise: Promise<IDBDatabase> | null = null
function openStore() {
  if (!storePromise) storePromise = new Promise((resolve, reject) => {
    const request = indexedDB.open('pte-live-im-web', 1)
    request.onupgradeneeded = () => { request.result.createObjectStore('keys'); request.result.createObjectStore('values') }
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
  return storePromise
}
function idbGet<T>(db: IDBDatabase, store: string, key: string): Promise<T | undefined> { return new Promise((resolve, reject) => { const request = db.transaction(store).objectStore(store).get(key); request.onsuccess = () => resolve(request.result as T | undefined); request.onerror = () => reject(request.error) }) }
function idbPut(db: IDBDatabase, store: string, value: unknown, key: string): Promise<void> { return new Promise((resolve, reject) => { const request = db.transaction(store, 'readwrite').objectStore(store).put(value, key); request.onsuccess = () => resolve(); request.onerror = () => reject(request.error) }) }

async function createResponseKey(): Promise<ResponseKey> { const privateKey = p256.utils.randomSecretKey(); return { privateKey, publicKey: base64Url(p256.getPublicKey(privateKey, false)) } }
function decryptResponse(root: Record<string, unknown>, key: ResponseKey): Record<string, unknown> { const salt = decodeBase64Url(stringOf(root.salt)); const nonce = decodeBase64Url(stringOf(root.nonce)); const shared = sharedSecret(key.privateKey, decodeBase64Url(stringOf(root.ephemeral_public_key))); const plain = gcm(deriveKey(shared, salt, 'pte-live-api-response-v1'), nonce, utf8('pte-live-api-response-v1')).decrypt(decodeBase64Url(stringOf(root.ciphertext))); return JSON.parse(utf8Decode(plain)) as Record<string, unknown> }
function wrapKey(contentKey: Uint8Array, recipientPublicKey: string) { const privateKey = p256.utils.randomSecretKey(); const nonce = crypto.getRandomValues(new Uint8Array(12)); const shared = sharedSecret(privateKey, decodeBase64Url(recipientPublicKey)); return { publicKey: base64Url(p256.getPublicKey(privateKey, false)), nonce: base64Url(nonce), ciphertext: base64Url(gcm(deriveKey(shared, nonce, 'pte-live-im-audit-wrap-v1'), nonce, utf8('pte-live-im-audit-wrap-v1')).encrypt(contentKey)) } }
function sharedSecret(privateKey: Uint8Array, publicKey: Uint8Array) { return p256.getSharedSecret(privateKey, publicKey, false).slice(1, 33) }
function deriveKey(shared: Uint8Array, salt: Uint8Array, label: string) { return hmac(sha256, salt, concat(shared, utf8(label))) }
function concat(first: Uint8Array, second: Uint8Array) { const result = new Uint8Array(first.length + second.length); result.set(first); result.set(second, first.length); return result }
function utf8(value: string) { return new TextEncoder().encode(value) }
function utf8Decode(value: Uint8Array) { return new TextDecoder().decode(value) }
function base64Url(value: Uint8Array) { return btoa(String.fromCharCode(...value)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') }
function decodeBase64Url(value: string) { const normalized = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '='); return Uint8Array.from(atob(normalized), (char) => char.charCodeAt(0)) }
function requestId() { return crypto.randomUUID() }
function stringOf(value: unknown) { return value === undefined || value === null ? '' : String(value) }
function numberOf(value: unknown) { const result = Number(value); return Number.isFinite(result) ? result : 0 }
function toConversation(raw: Record<string, unknown>): PteConversation {
  return {
    id: numberOf(raw.id),
    type: stringOf(raw.type),
    title: stringOf(raw.title),
    avatar: stringOf(raw.avatar) || undefined,
    singleKey: stringOf(raw.single_key || raw.singleKey) || undefined,
    lastMessageSeq: numberOf(raw.last_message_seq ?? raw.lastMessageSeq),
    lastMessageSnapshot: stringOf(raw.last_message_snapshot ?? raw.lastMessageSnapshot) || undefined,
    lastMessageAt: numberOf(raw.last_message_at ?? raw.lastMessageAt),
    unreadCount: numberOf(raw.unread_count ?? raw.unreadCount),
  }
}
function contactPage(data: Record<string, unknown>) { const list = Array.isArray(data.list) ? data.list.map((value) => { const raw = value as Record<string, unknown>; return { userId: stringOf(raw.userId), remark: stringOf(raw.remark), nickname: stringOf(raw.nickname), avatar: stringOf(raw.avatar), gender: stringOf(raw.gender), followedAt: numberOf(raw.followedAt) } }) : []; return { list, nextCursor: stringOf(data.nextCursor), hasMore: Boolean(data.hasMore) } }

function normalizeMediaContentType(file: Blob, mediaType: 'image' | 'video' | 'voice' | 'file'): string {
  const raw = String((file as File).type || '').toLowerCase().split(';')[0].trim()
  const allowed: Record<string, string[]> = {
    image: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
    video: ['video/mp4', 'video/webm', 'video/quicktime'],
    voice: ['audio/aac', 'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav'],
    file: [
      'application/pdf', 'text/plain', 'text/csv', 'application/json', 'application/zip',
      'application/x-7z-compressed', 'application/vnd.ms-excel', 'application/vnd.ms-powerpoint',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ],
  }
  if (raw && allowed[mediaType]?.includes(raw)) return raw
  if (mediaType === 'image') return 'image/jpeg'
  if (mediaType === 'video') return 'video/mp4'
  if (mediaType === 'voice') return 'audio/mpeg'
  throw new Error('不支持的媒体类型')
}

function businessContent(content: PteIMBusinessContent): Record<string, unknown> {
  return {
    businessId: content.businessId,
    title: content.title,
    ...(content.subtitle ? { subtitle: content.subtitle } : {}),
    ...(content.actionUrl ? { actionUrl: content.actionUrl } : {}),
  }
}

function parseReactions(raw: unknown): PteIMMessageReaction[] | undefined {
  if (!Array.isArray(raw)) return undefined
  const list = raw.map((item) => {
    const row = (item || {}) as Record<string, unknown>
    return {
      emoji: stringOf(row.emoji),
      count: numberOf(row.count),
      reactedByMe: Boolean(row.reacted_by_me ?? row.reactedByMe),
    }
  }).filter((item) => item.emoji)
  return list.length ? list : undefined
}

/** Canonical Web chat client name aligned with native PteIMSDK. */
export { PteLiveIMWebClient as PteIMWebSDK }
