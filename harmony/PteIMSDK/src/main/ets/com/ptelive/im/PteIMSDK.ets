import { Context } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import webSocket from '@ohos.net.webSocket'
import http from '@ohos.net.http'
import util from '@ohos.util'
import { PteIMAppearance, PteIMBaseConfig, PteIMBusinessContent, PteIMConversation, PteIMConversationPage, PteIMLanguage, PteIMListener, PteIMLocation, PteIMLoginConfig, PteIMMedia, PteIMMessage, PteIMMessagePage, PteIMMessageType, PteIMRemoteConversation, PteIMRemoteMessage, PteIMSendState, PteIMThemeMode, PteIMVoice, PteIMWireMessage } from './IMModels'
import { PteIMSqliteStore } from './IMSqliteStore'
import { PteIME2EE } from './PteIME2EE'
import { PteIMResponseCrypto } from './PteIMResponseCrypto'

type WireObject = Record<string, Object>
interface PteIMSendMessagePayload { clientMsgId: string; conversationId: string; type: PteIMMessageType; e2ee: WireObject }
interface PteIMDecryptedMessage extends WireObject { clientMsgId: Object; serverMsgId: Object; serverSeq: Object; conversationId: Object; senderId: Object; type: Object; createdAt: Object; content: WireObject }

interface PteIMHttpRequestOptions extends http.HttpRequestOptions {}

class PteIMRequestBody {
  userSig: string = ''
  syncCursor: string = ''
  pageSize: number = 0
  limit: number = 0
  page: number = 0
  peerUserId: number = 0
  title: string = ''
  memberIds: number[] = []
  avatar: string = ''
  conversationId: number = 0
  seq: number = 0
  beforeSeq: number = 0
  mediaType: string = ''
  contentType: string = ''
  contentLength: number = 0
  serverMsgId: string = ''
}

class PteIMEnvelope {
  protocolVersion: number = 1
  action: string = ''
  requestId: string = ''
  sdkAppId: number = 0
  userId: string = ''
  userSig: string = ''
  payload: Object = new PteIMRequestBody()
}

/** Native HarmonyOS IM runtime. The database is initialized before the client is returned. */
export class PteIMSDK {
  private socket: webSocket.WebSocket | null = null
  private readonly listeners: PteIMListener[] = []
  private stopped: boolean = true
  private connected: boolean = false
  private reconnectAttempt: number = 0
  private reconnectTimer: number = -1
  private outboxTimer: number = -1
  private syncing: boolean = false
  private appearance: PteIMAppearance

  private config: PteIMLoginConfig
  private base: PteIMBaseConfig
  private store: PteIMSqliteStore
  private e2ee: PteIME2EE

  constructor(config: PteIMLoginConfig, base: PteIMBaseConfig, store: PteIMSqliteStore) {
    this.config = config
    this.base = base
    this.store = store
    this.e2ee = new PteIME2EE(config, store)
    this.appearance = new PteIMAppearance(base.themeMode, base.language)
  }

  static configure(context: Context, baseConfig: PteIMBaseConfig): PteIMSDKBootstrap {
    return new PteIMSDKBootstrap(context, baseConfig)
  }

  addListener(listener: PteIMListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener)
  }

  removeListener(listener: PteIMListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) this.listeners.splice(index, 1)
  }

  start(): void {
    this.stopped = false
    this.cancelTimers()
    if (this.socket === null) void this.registerAndConnect()
  }

  stop(): void {
    this.stopped = true
    this.cancelTimers()
    const wasConnected = this.connected
    this.connected = false
    if (this.socket !== null) this.socket.close()
    this.socket = null
    if (wasConnected) this.listeners.forEach((listener: PteIMListener) => listener.onConnectionChanged(false))
  }

  renewUserSig(userSig: string): void {
    if (userSig.length === 0) throw new Error('userSig is required')
    this.config.userSig = userSig
    const body = new PteIMRequestBody(); body.userSig = userSig
    this.sendEnvelope('renew_user_sig', body)
  }

  updateAppearance(themeMode: PteIMThemeMode | null = null, language: PteIMLanguage | null = null): PteIMAppearance {
    const before = this.appearance
    this.appearance = new PteIMAppearance(themeMode === null ? before.themeMode : themeMode, language === null ? before.language : language)
    if (before.themeMode !== this.appearance.themeMode) this.listeners.forEach((listener: PteIMListener) => listener.onThemeModeChanged(this.appearance.themeMode))
    if (before.language !== this.appearance.language) this.listeners.forEach((listener: PteIMListener) => listener.onLanguageChanged(this.appearance.language))
    return this.appearance
  }

  currentAppearance(): PteIMAppearance { return this.appearance }
  currentUserId(): string { return this.config.userId }

  async sendText(conversationId: string, text: string): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.TEXT, text)) }
  async sendEmoji(conversationId: string, packageId: string, emojiId: string): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.EMOJI, '', packageId, emojiId)) }
  async sendImage(conversationId: string, media: PteIMMedia): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.IMAGE, '', '', '', media)) }
  async sendVideo(conversationId: string, media: PteIMMedia): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.VIDEO, '', '', '', media)) }
  /** Uploads an image through apiDomain, then enqueues it with a stable clientMsgId. */
  async uploadAndSendImage(conversationId: string, filePath: string, mimeType: string = 'image/jpeg'): Promise<PteIMMessage> {
    return await this.uploadAndSendMedia(conversationId, filePath, PteIMMessageType.IMAGE, mimeType)
  }
  /** Uploads a video through apiDomain, then enqueues it with a stable clientMsgId. */
  async uploadAndSendVideo(conversationId: string, filePath: string, mimeType: string = 'video/mp4'): Promise<PteIMMessage> {
    return await this.uploadAndSendMedia(conversationId, filePath, PteIMMessageType.VIDEO, mimeType)
  }
  async uploadAndSendVoice(conversationId: string, filePath: string, durationMs: number, waveform: string = '', mimeType: string = 'audio/mpeg'): Promise<PteIMMessage> {
    if (durationMs <= 0) throw new Error('durationMs must be positive')
    return await this.uploadAndSendMedia(conversationId, filePath, PteIMMessageType.VOICE, mimeType, durationMs, waveform)
  }
  async sendVoice(conversationId: string, voice: PteIMVoice): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.VOICE, '', '', '', null, voice)) }
  async sendLocation(conversationId: string, location: PteIMLocation): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.LOCATION, '', '', '', null, null, location)) }
  async sendGift(conversationId: string, content: PteIMBusinessContent): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.GIFT, '', '', '', null, null, null, content)) }
  async sendRedPacket(conversationId: string, content: PteIMBusinessContent): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.RED_PACKET, '', '', '', null, null, null, content)) }
  async sendOrder(conversationId: string, content: PteIMBusinessContent): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.ORDER, '', '', '', null, null, null, content)) }

  async syncNow(): Promise<void> {
    if (this.syncing) return
    this.syncing = true
    try {
      const body = new PteIMRequestBody(); body.syncCursor = await this.store.cursor(); body.pageSize = 200
      const payload = await this.sdkRequest('/v1/im/sync', body)
      const messages = await this.messagesFromResponse(payload)
      const nextCursor = this.stringValue(payload, 'nextCursor')
      await this.store.apply(messages, nextCursor)
      messages.forEach((message: PteIMMessage) => this.listeners.forEach((listener: PteIMListener) => listener.onMessage(message)))
      if (this.boolValue(payload, 'hasMore')) {
        this.syncing = false
        await this.syncNow()
      }
    } catch (error) {
      this.emitError(error)
    } finally {
      this.syncing = false
    }
  }

  async localMessages(conversationId: string, beforeCreatedAt: number = 0, limit: number = 50): Promise<PteIMMessage[]> {
    const stored = await this.store.localMessages(conversationId, beforeCreatedAt, limit)
    return stored.map((row) => this.messageFromJson(row.payload, row.serverMsgId, row.serverSeq, row.createdAt, row.state))
  }

  async localConversations(limit: number = 100): Promise<PteIMConversation[]> {
    const stored = await this.store.localConversations(limit)
    return stored.map((row) => new PteIMConversation(row.conversationId, this.messageFromJson(row.stored.payload, row.stored.serverMsgId, row.stored.serverSeq, row.stored.createdAt, row.stored.state), row.stored.createdAt))
  }

  async fetchConversationPage(page: number = 1, pageSize: number = 50): Promise<PteIMConversationPage> {
    if (page <= 0 || pageSize <= 0 || pageSize > 200) throw new Error('invalid conversation page')
    const body = new PteIMRequestBody(); body.page = page; body.pageSize = pageSize
    const data = await this.sdkRequest('/v1/im/conversations', body)
    const values = data['list'] as Object[]
    const items: PteIMRemoteConversation[] = values === undefined || values === null ? [] : values.map((value: Object) => this.remoteConversation(value as WireObject))
    return new PteIMConversationPage(this.numberValue(data, 'total'), items)
  }

  async openSingleConversation(peerUserId: number): Promise<PteIMRemoteConversation> {
    if (peerUserId <= 0) throw new Error('peerUserId must be positive')
    const body = new PteIMRequestBody(); body.peerUserId = peerUserId
    return this.remoteConversation(await this.sdkRequest('/v1/im/conversations/open-single', body))
  }

  async createGroupConversation(title: string, memberIds: number[] = [], avatar: string = ''): Promise<PteIMRemoteConversation> {
    if (title.length === 0 || memberIds.some((memberId: number) => memberId <= 0)) throw new Error('invalid group parameters')
    const body = new PteIMRequestBody(); body.title = title; body.memberIds = memberIds; body.avatar = avatar
    return this.remoteConversation(await this.sdkRequest('/v1/im/conversations/create-group', body))
  }

  async markConversationRead(conversationId: number, seq: number = 0): Promise<void> {
    if (conversationId <= 0 || seq < 0) throw new Error('invalid read cursor')
    const body = new PteIMRequestBody(); body.conversationId = conversationId; body.seq = seq
    await this.sdkRequest('/v1/im/conversations/read', body)
  }

  async fetchMessageHistory(conversationId: number, beforeSeq: number = 0, limit: number = 50): Promise<PteIMMessagePage> {
    if (conversationId <= 0 || beforeSeq < 0 || limit <= 0 || limit > 200) throw new Error('invalid message history page')
    const body = new PteIMRequestBody(); body.conversationId = conversationId; body.beforeSeq = beforeSeq; body.limit = limit
    const data = await this.sdkRequest('/v1/im/conversations/messages', body)
    const values = data['list'] as Object[]
    const items: PteIMRemoteMessage[] = values === undefined || values === null ? [] : values.map((value: Object) => this.remoteMessage(value as WireObject))
    return new PteIMMessagePage(items)
  }

  private async send(message: PteIMMessage): Promise<PteIMMessage> {
    if (!/^[1-9][0-9]*$/.test(message.conversationId)) throw new Error('conversationId must be a positive numeric string returned by openSingleConversation or createGroupConversation')
    message.senderId = this.config.userId
    await this.store.enqueue(message)
    this.listeners.forEach((listener: PteIMListener) => listener.onMessageStateChanged(message.clientMsgId, PteIMSendState.PENDING))
    await this.flushOutbox()
    return message
  }

  private async uploadAndSendMedia(conversationId: string, filePath: string, type: PteIMMessageType, mimeType: string, voiceDurationMs: number = 0, waveform: string = ''): Promise<PteIMMessage> {
    if (!/^[1-9][0-9]*$/.test(conversationId)) throw new Error('conversationId must be a positive numeric string returned by openSingleConversation or createGroupConversation')
    const message = new PteIMMessage(conversationId, type, '', '', '', null, null, null, null, '', 0, PteIMSendState.UPLOADING)
    message.senderId = this.config.userId
    // Uploading rows are visible to cache-first UI but deliberately not in the durable outbox.
    await this.store.replaceQueued(message)
    this.listeners.forEach((listener: PteIMListener) => listener.onMessageStateChanged(message.clientMsgId, PteIMSendState.UPLOADING))
    try {
      const uploaded = await this.uploadMedia(filePath, type, mimeType)
      if (type === PteIMMessageType.VOICE) message.voice = new PteIMVoice(uploaded.url, voiceDurationMs, waveform, uploaded.sizeBytes)
      else message.media = uploaded
      message.state = PteIMSendState.PENDING
      await this.store.enqueue(message)
      this.listeners.forEach((listener: PteIMListener) => listener.onMessageStateChanged(message.clientMsgId, PteIMSendState.PENDING))
      await this.flushOutbox()
    } catch (error) {
      message.state = PteIMSendState.FAILED
      await this.store.markFailed(message.clientMsgId)
      this.listeners.forEach((listener: PteIMListener) => listener.onMessageStateChanged(message.clientMsgId, PteIMSendState.FAILED))
      this.emitError(error)
    }
    return message
  }

  private async uploadMedia(filePath: string, type: PteIMMessageType, mimeType: string): Promise<PteIMMedia> {
    const bytes = this.readFile(filePath)
    const body = new PteIMRequestBody(); body.mediaType = type; body.contentType = mimeType; body.contentLength = bytes.byteLength
    const credential = await this.apiImRequest('/v1/im/media/put-url', body)
    const key = this.stringValue(credential, 'key')
    const uploadUrl = this.stringValue(credential, 'uploadUrl')
    const headers = credential['headers'] as WireObject
    if (key.length === 0 || uploadUrl.length === 0 || headers === undefined || headers === null) throw new Error('media credential response is invalid')
    const request = http.createHttp()
    try {
      const requestHeaders = new Map<string, string>()
      requestHeaders.set('Content-Type', this.stringValue(headers, 'Content-Type'))
      const options: PteIMHttpRequestOptions = {
        method: http.RequestMethod.PUT,
        header: requestHeaders,
        extraData: bytes.buffer
      }
      const response = await request.request(uploadUrl, options)
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`COS upload failed with HTTP ${response.responseCode}`)
      return new PteIMMedia(key, '', '', 0, 0, 0, bytes.byteLength)
    } finally { request.destroy() }
  }

  private readFile(filePath: string): Uint8Array {
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
    try {
      const size = fileIo.statSync(file.fd).size
      if (size <= 0) throw new Error('media file is empty')
      const buffer = new ArrayBuffer(size)
      const read = fileIo.readSync(file.fd, buffer)
      if (read !== size) throw new Error('could not read the complete media file')
      return new Uint8Array(buffer)
    } finally { fileIo.closeSync(file) }
  }

  private fileName(filePath: string, type: PteIMMessageType): string {
    const parts = filePath.split('/')
    const name = parts.length > 0 ? parts[parts.length - 1] : ''
    return name.length > 0 ? name.replace(/"/g, '') : `media-${type === PteIMMessageType.IMAGE ? 'image' : 'video'}`
  }

  private connect(): void {
    this.socket = webSocket.createWebSocket()
    this.socket.on('open', () => { this.onOpen() })
    this.socket.on('message', (_error: Error | null, value: string | ArrayBuffer) => {
      if (typeof value === 'string') void this.handleInbound(value)
      else void this.handleInbound(util.TextDecoder.create('utf-8').decode(new Uint8Array(value)))
    })
    this.socket.on('close', () => { this.onClose() })
    this.socket.on('error', (error: Error) => { this.emitError(error); this.onClose() })
    this.socket.connect(this.webSocketURL(), (error: Error) => { if (error !== null) { this.emitError(error); this.onClose() } })
  }

  // The configured IM service validates UserSig at WSS upgrade; use the same query contract as H5/mini-program.
  private webSocketURL(): string {
    const separator = this.base.imDomain.indexOf('?') >= 0 ? '&' : '?'
    return this.base.imDomain + separator + 'sdkAppID=' + encodeURIComponent(this.config.sdkAppId.toString()) +
      '&identifier=' + encodeURIComponent(this.config.userId) + '&userSig=' + encodeURIComponent(this.config.userSig)
  }

  private async onOpen(): Promise<void> {
    this.reconnectAttempt = 0
    this.connected = true
    this.listeners.forEach((listener: PteIMListener) => listener.onConnectionChanged(true))
    const body = new PteIMRequestBody(); body.syncCursor = await this.store.cursor()
    this.sendEnvelope('login', body)
    await this.flushOutbox()
    await this.syncNow()
  }

  private onClose(): void {
    const wasConnected = this.connected
    this.connected = false
    this.socket = null
    if (wasConnected) this.listeners.forEach((listener: PteIMListener) => listener.onConnectionChanged(false))
    if (!this.stopped) this.scheduleReconnect()
  }

  private async handleInbound(raw: string): Promise<void> {
    try {
      const envelope = JSON.parse(raw) as WireObject
      const action = this.stringValue(envelope, 'action')
      const payload = envelope['payload'] as WireObject
      if (action === 'message') {
        const message = await this.messageFromRemoteWire(payload)
        await this.store.apply([message], this.stringValue(envelope, 'syncCursor'))
        this.listeners.forEach((listener: PteIMListener) => listener.onMessage(message))
        const body = new PteIMRequestBody(); body.serverMsgId = message.serverMsgId
        this.sendEnvelope('ack', body)
      } else if (action === 'ack') {
        const clientMsgId = this.stringValue(payload, 'clientMsgId')
        this.store.markSent(clientMsgId, this.stringValue(payload, 'serverMsgId'), this.numberValue(payload, 'serverSeq')).then(() => {
          this.listeners.forEach((listener: PteIMListener) => listener.onMessageStateChanged(clientMsgId, PteIMSendState.SENT))
        }).catch((error: Error) => this.emitError(error))
      } else if (action === 'user_sig_will_expire') this.listeners.forEach((listener: PteIMListener) => listener.onUserSigWillExpire())
      else if (action === 'user_sig_expired') this.listeners.forEach((listener: PteIMListener) => listener.onUserSigExpired())
      else if (action === 'sync_required') this.syncNow()
    } catch (error) { this.emitError(error) }
  }

  private sendEnvelope(action: string, payload: Object): void {
    if (!this.connected || this.socket === null) return
    const envelope = new PteIMEnvelope()
    envelope.action = action
    envelope.requestId = `${Date.now()}-${Math.random()}`
    envelope.sdkAppId = this.config.sdkAppId
    envelope.userId = this.config.userId
    envelope.userSig = this.config.userSig
    envelope.payload = payload
    this.socket.send(JSON.stringify(envelope), (error: Error) => { if (error !== null) this.emitError(error) })
  }

  private async flushOutbox(): Promise<void> {
    if (!this.connected || this.stopped) return
    try {
      const now = Date.now()
      const due = await this.store.dueOutbox(now)
      for (let index = 0; index < due.length; index++) {
        const message = this.messageFromJson(due[index].payload, due[index].serverMsgId, due[index].serverSeq, due[index].createdAt, due[index].state)
        await this.store.recordOutboxAttempt(message.clientMsgId, now)
        const e2ee = await this.e2ee.encrypt(message, (path: string, body: WireObject): Promise<Object> => this.sdkRequest(path, body))
        const payload: PteIMSendMessagePayload = {
          clientMsgId: message.clientMsgId, conversationId: message.conversationId, type: message.type, e2ee,
        }
        this.sendEnvelope('send_message', payload)
      }
      const next = await this.store.nextOutboxRetryAt()
      if (next > 0) this.outboxTimer = setTimeout(() => { this.flushOutbox() }, Math.min(Math.max(next - Date.now(), 100), 30000))
    } catch (error) { this.emitError(error) }
  }

  private scheduleReconnect(): void {
    const delay = Math.min(1000 * Math.pow(2, Math.min(this.reconnectAttempt++, 5)), 30000)
    this.reconnectTimer = setTimeout(() => { if (!this.stopped && this.socket === null) this.connect() }, delay)
  }

  private cancelTimers(): void {
    if (this.reconnectTimer >= 0) clearTimeout(this.reconnectTimer)
    if (this.outboxTimer >= 0) clearTimeout(this.outboxTimer)
    this.reconnectTimer = -1; this.outboxTimer = -1
  }

  private resolveMedia(media: PteIMMedia): PteIMMedia { return new PteIMMedia(this.resolveCosUrl(media.url), this.resolveCosUrl(media.thumbnailUrl), this.resolveCosUrl(media.coverUrl), media.width, media.height, media.durationMs, media.sizeBytes) }
  private async registerAndConnect(): Promise<void> {
    try {
      await this.e2ee.register((path: string, body: WireObject): Promise<Object> => this.sdkRequest(path, body))
      if (!this.stopped && this.socket === null) this.connect()
    } catch (error) { this.emitError(error) }
  }
  private async sdkRequest(path: string, body: Object): Promise<WireObject> {
    const request = http.createHttp()
    try {
      const requestHeaders = this.apiRequestHeaders()
      const responseKey = await PteIMResponseCrypto.createRequestKey()
      requestHeaders.set('X-Pte-Response-Public-Key', responseKey.publicKey)
      const options: PteIMHttpRequestOptions = { method: http.RequestMethod.POST, header: requestHeaders, extraData: JSON.stringify(body) }
      const response = await request.request(`${this.base.apiDomain.replace(/\/$/, '')}${path}`, options)
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`IM API failed with HTTP ${response.responseCode}`)
      const root = await PteIMResponseCrypto.decryptResponse(JSON.parse(response.result.toString()) as WireObject, responseKey)
      if (this.numberValue(root, 'code') !== 1) throw new Error(this.stringValue(root, 'msg'))
      return root['data'] as WireObject
    } finally { request.destroy() }
  }
  private async apiImRequest(path: string, body: PteIMRequestBody): Promise<WireObject> {
    const request = http.createHttp()
    try {
      const requestHeaders = this.apiRequestHeaders()
      const options: PteIMHttpRequestOptions = { method: http.RequestMethod.POST, header: requestHeaders, extraData: JSON.stringify(body) }
      const response = await request.request(`${this.base.apiDomain.replace(/\/$/, '')}${path}`, options)
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`IM API failed with HTTP ${response.responseCode}`)
      const root = JSON.parse(response.result.toString()) as WireObject
      if (this.numberValue(root, 'code') !== 0) throw new Error(this.stringValue(root, 'msg'))
      return root['data'] as WireObject
    } finally { request.destroy() }
  }
  private remoteConversation(value: WireObject): PteIMRemoteConversation { return new PteIMRemoteConversation(this.numberValue(value, 'id'), this.stringValue(value, 'type'), this.stringValue(value, 'title'), this.stringValue(value, 'avatar'), this.numberValue(value, 'last_message_seq'), this.stringValue(value, 'last_message_snapshot'), this.numberValue(value, 'last_message_at'), this.numberValue(value, 'unread_count')) }
  private remoteMessage(value: WireObject): PteIMRemoteMessage { return new PteIMRemoteMessage(this.numberValue(value, 'message_id'), this.numberValue(value, 'conversation_id'), this.numberValue(value, 'sender_id'), this.stringValue(value, 'client_msg_id'), this.stringValue(value, 'msg_type'), this.stringValue(value, 'content'), this.stringValue(value, 'payload'), this.numberValue(value, 'seq'), this.numberValue(value, 'sent_at'), this.numberValue(value, 'recalled_at')) }
  private apiRequestHeaders(): Map<string, string> {
    const headers = new Map<string, string>()
    headers.set('Content-Type', 'application/json')
    headers.set('Authorization', `Bearer ${this.config.userSig}`)
    headers.set('X-Pte-Sdk-AppId', this.config.sdkAppId.toString())
    headers.set('X-Pte-User-Id', this.config.userId)
    return headers
  }
  private resolveCosUrl(value: string): string { return value.length === 0 || value.startsWith('https://') ? value : `${this.base.cosDomain.replace(/\/$/, '')}/${value.replace(/^\//, '')}` }
  private emitError(error: Object): void { const value = error instanceof Error ? error : new Error(error.toString()); this.listeners.forEach((listener: PteIMListener) => listener.onError(value)) }

  private async messagesFromResponse(payload: WireObject): Promise<PteIMMessage[]> {
    const raw = payload['messages'] as Object[]
    if (raw === undefined || raw === null) return []
    const values: PteIMMessage[] = []
    for (let index = 0; index < raw.length; index++) values.push(await this.messageFromRemoteWire(raw[index] as WireObject))
    return values
  }
  private messageFromJson(raw: string, serverMsgId: string, serverSeq: number, createdAt: number, state: PteIMSendState): PteIMMessage {
    const message = this.messageFromWire(JSON.parse(raw) as WireObject)
    message.serverMsgId = serverMsgId; message.serverSeq = serverSeq; message.createdAt = createdAt; message.state = state
    return message
  }
  private messageFromWire(value: WireObject): PteIMMessage {
    const content = value['content'] as WireObject
    const type = this.stringValue(value, 'type') as PteIMMessageType
    const media = type === PteIMMessageType.IMAGE || type === PteIMMessageType.VIDEO ? new PteIMMedia(this.resolveCosUrl(this.stringValue(content, 'url')), this.resolveCosUrl(this.stringValue(content, 'thumbnailUrl')), this.resolveCosUrl(this.stringValue(content, 'coverUrl')), this.numberValue(content, 'width'), this.numberValue(content, 'height'), this.numberValue(content, 'durationMs'), this.numberValue(content, 'sizeBytes')) : null
    const voice = type === PteIMMessageType.VOICE ? new PteIMVoice(this.resolveCosUrl(this.stringValue(content, 'url')), this.numberValue(content, 'durationMs'), this.stringValue(content, 'waveform'), this.numberValue(content, 'sizeBytes')) : null
    const location = type === PteIMMessageType.LOCATION ? new PteIMLocation(this.numberValue(content, 'latitude'), this.numberValue(content, 'longitude'), this.stringValue(content, 'name'), this.stringValue(content, 'address')) : null
    const business = type === PteIMMessageType.GIFT || type === PteIMMessageType.RED_PACKET || type === PteIMMessageType.ORDER ? new PteIMBusinessContent(this.stringValue(content, 'businessId'), this.stringValue(content, 'title'), this.stringValue(content, 'subtitle'), this.stringValue(content, 'actionUrl')) : null
    const message = new PteIMMessage(this.stringValue(value, 'conversationId'), type, this.stringValue(content, 'text'), this.stringValue(content, 'packageId'), this.stringValue(content, 'emojiId'), media, voice, location, business, this.stringValue(value, 'clientMsgId'), this.numberValue(value, 'createdAt'), PteIMSendState.SENT)
    message.senderId = this.stringValue(value, 'senderId')
    message.serverMsgId = this.stringValue(value, 'serverMsgId'); message.serverSeq = this.numberValue(value, 'serverSeq')
    return message
  }
  private async messageFromRemoteWire(value: WireObject): Promise<PteIMMessage> {
    const e2ee = value['e2ee'] as WireObject
    if (e2ee === undefined || e2ee === null) return this.messageFromWire(value)
    const content = await this.e2ee.decrypt(e2ee)
    const decrypted: PteIMDecryptedMessage = {
      clientMsgId: value['clientMsgId'], serverMsgId: value['serverMsgId'], serverSeq: value['serverSeq'],
      conversationId: value['conversationId'], senderId: value['senderId'], type: value['type'], createdAt: value['createdAt'], content,
    }
    return this.messageFromWire(decrypted)
  }
  private stringValue(value: WireObject, key: string): string { const item = value[key]; return item === undefined || item === null ? '' : item.toString() }
  private numberValue(value: WireObject, key: string): number { const item = value[key]; return item === undefined || item === null ? 0 : Number(item.toString()) }
  private boolValue(value: WireObject, key: string): boolean { return this.stringValue(value, key) === 'true' }
}

export class PteIMSDKBootstrap {
  private context: Context
  private baseConfig: PteIMBaseConfig
  constructor(context: Context, baseConfig: PteIMBaseConfig) { this.context = context; this.baseConfig = baseConfig }

  async login(loginConfig: PteIMLoginConfig): Promise<PteIMSDK> {
    this.baseConfig.validate(); loginConfig.validate()
    const storeName = `pte_live_im_${loginConfig.sdkAppId}_${loginConfig.userId.replace(/[^A-Za-z0-9_]/g, '_')}`
    const client = new PteIMSDK(loginConfig, this.baseConfig, await PteIMSqliteStore.open(this.context, storeName))
    client.start()
    return client
  }
}
