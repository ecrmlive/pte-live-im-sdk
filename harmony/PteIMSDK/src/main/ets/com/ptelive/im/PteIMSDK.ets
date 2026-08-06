import { Context } from '@kit.AbilityKit'
import { fileIo } from '@kit.CoreFileKit'
import webSocket from '@ohos.net.webSocket'
import http from '@ohos.net.http'
import util from '@ohos.util'
import { PteIMAppearance, PteIMBaseConfig, PteIMBusinessContent, PteIMContact, PteIMContactPage, PteIMConversation, PteIMConversationPage, PteIMDefaultSetting, PteIMGender, PteIMGroupPage, PteIMLanguage, PteIMListener, PteIMLocation, PteIMLoginConfig, PteIMMedia, PteIMMember, PteIMMemberPage, PteIMMessage, PteIMMessagePage, PteIMMessageReaction, PteIMMessageType, PteIMPushDevice, PteIMPushPlatform, PteIMRemoteConversation, PteIMRemoteMessage, PteIMSendState, PteIMStateChange, PteIMStateChangePage, PteIMThemeMode, PteIMUserProfile, PteIMUserProfileUpdate, PteIMVoice, PteIMWireContent, PteIMWireMessage, PteIMUserSigRefreshResult } from './IMModels'
import { PteIMRdbStore, PteIMStoredRemoteConversation } from './PteIMRdbStore'
import { PteIME2EE } from './PteIME2EE'
import { PteIMResponseCrypto } from './PteIMResponseCrypto'
import { PteIMSceneClient, PteIMSceneCredentials } from './PteIMSceneClient'

type WireObject = Record<string, Object>
interface PteIMSendMessagePayload { clientMsgId: string; conversationId: string; type: PteIMMessageType; e2ee: WireObject; quoteMessageId: string }
interface PteIMDecryptedMessage extends WireObject { clientMsgId: Object; serverMsgId: Object; serverSeq: Object; conversationId: Object; senderId: Object; type: Object; createdAt: Object; content: Object }

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
  messageId: string = ''
  emoji: string = ''
  field: string = ''
  value: string = ''
  cursor: string = ''
  targetUserId: number = 0
  memberId: number = 0
  remark: string = ''
  deviceId: string = ''
  platform: string = ''
  token: string = ''
  notificationEnabled: boolean = true
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
  private userSigRefreshTimer: number = -1
  private userSigRefreshInFlight: boolean = false
  private syncing: boolean = false
  private conversationSyncing: boolean = false
  private appearance: PteIMAppearance

  private config: PteIMLoginConfig
  private base: PteIMBaseConfig
  private store: PteIMRdbStore
  private e2ee: PteIME2EE
  /** Optional Commerce extension; it shares UserSig and no additional socket. */
  readonly commerce: PteIMCommerce

  constructor(config: PteIMLoginConfig, base: PteIMBaseConfig, store: PteIMRdbStore) {
    this.config = config
    this.base = base
    this.store = store
    this.e2ee = new PteIME2EE(config, store)
    this.appearance = new PteIMAppearance(base.themeMode, base.language)
    this.commerce = new PteIMCommerce(this)
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
    this.scheduleUserSigRefresh()
    if (this.socket === null) void this.registerAndConnect()
  }

  stop(): void {
    this.stopped = true
    this.cancelTimers()
    const wasConnected = this.connected
    this.connected = false
    try {
      if (this.socket !== null) this.socket.close()
    } catch (error) { this.emitError(new Error(`PteIM WebSocket close failed: ${String(error)}`)) }
    this.socket = null
    if (wasConnected) this.listeners.forEach((listener: PteIMListener) => listener.onConnectionChanged(false))
  }

  /** True once E2EE registration and the chat WebSocket handshake complete. */
  isConnected(): boolean { return this.connected && !this.stopped }

  /** Applies a Provider result; UI code never submits a UserSig directly. */
  private applyRefreshedUserSig(userSig: string, expireAt: number): void {
    if (userSig.length === 0) throw new Error('userSig is required')
    this.config.userSig = userSig
    if (expireAt > 0) this.config.userSigExpireAt = expireAt
    this.scheduleUserSigRefresh()
    const body = new PteIMRequestBody(); body.userSig = userSig
    this.sendEnvelope('renew_user_sig', body)
  }

  async refreshUserSig(force: boolean = false): Promise<boolean> {
    const provider = this.config.userSigProvider
    if (this.stopped || provider === null) return false
    const now = Math.floor(Date.now() / 1000)
    if (!force && this.config.userSigExpireAt > now + 300) { this.scheduleUserSigRefresh(); return true }
    if (this.userSigRefreshInFlight) return false
    this.userSigRefreshInFlight = true
    try {
      const renewed: PteIMUserSigRefreshResult = await provider.refreshUserSig()
      if (renewed.userSig.length === 0 || renewed.expireAt <= Math.floor(Date.now() / 1000)) throw new Error('invalid UserSig refresh response')
      this.applyRefreshedUserSig(renewed.userSig, renewed.expireAt)
      void this.syncNow(); void this.syncConversationsNow()
      return true
    } catch (error) {
      const value = error instanceof Error ? error : new Error(String(error))
      this.listeners.forEach((listener: PteIMListener) => listener.onUserSigRefreshFailed(value))
      return false
    } finally { this.userSigRefreshInFlight = false }
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

  /** Creates an independent scene WSS client (room-scoped UserSig, separate from chat). */
  createSceneClient(credentials: PteIMSceneCredentials): PteIMSceneClient {
    // Native OpenHarmony WebSocket may send a non-browser Origin by default.
    // Give scene sockets the same configured business origin as chat so a
    // server's browser-origin allowlist can still protect browser clients.
    if (credentials.origin.length === 0) credentials.origin = this.webSocketOrigin()
    return new PteIMSceneClient(credentials)
  }

  async sendText(conversationId: string, text: string): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.TEXT, text)) }
  async sendEmoji(conversationId: string, packageId: string, emojiId: string): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.EMOJI, '', packageId, emojiId)) }
  async sendImage(conversationId: string, media: PteIMMedia): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.IMAGE, '', '', '', media)) }
  async sendVideo(conversationId: string, media: PteIMMedia): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.VIDEO, '', '', '', media)) }
  /** Sends a file descriptor whose url is a durable COS key, not a temporary PUT URL. */
  async sendFile(conversationId: string, media: PteIMMedia): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.FILE, '', '', '', media)) }
  /** Uploads an image through apiDomain, then enqueues it with a stable clientMsgId. */
  async uploadAndSendImage(conversationId: string, filePath: string, mimeType: string = 'image/jpeg'): Promise<PteIMMessage> {
    return await this.uploadAndSendMedia(conversationId, filePath, PteIMMessageType.IMAGE, mimeType)
  }
  /** Uploads a video through apiDomain, then enqueues it with a stable clientMsgId. */
  async uploadAndSendVideo(conversationId: string, filePath: string, mimeType: string = 'video/mp4'): Promise<PteIMMessage> {
    return await this.uploadAndSendMedia(conversationId, filePath, PteIMMessageType.VIDEO, mimeType)
  }
  /** mimeType must be one of the server allow-listed document/archive MIME types. */
  async uploadAndSendFile(conversationId: string, filePath: string, mimeType: string): Promise<PteIMMessage> {
    if (mimeType.length === 0) throw new Error('file mimeType is required')
    return await this.uploadAndSendMedia(conversationId, filePath, PteIMMessageType.FILE, mimeType)
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
  /** Sends a host-defined message envelope. The server must explicitly allow the custom type. */
  async sendCustom(conversationId: string, content: PteIMBusinessContent): Promise<PteIMMessage> { return await this.send(new PteIMMessage(conversationId, PteIMMessageType.CUSTOM, '', '', '', null, null, null, content)) }
  /** Sends text while retaining quote metadata for UIKit and other clients. */
  async sendTextWithQuote(conversationId: string, text: string, quoteClientMsgId: string, quoteServerMsgId: string, quoteText: string): Promise<PteIMMessage> {
    const message = new PteIMMessage(conversationId, PteIMMessageType.TEXT, text)
    message.quoteClientMsgId = quoteClientMsgId
    message.quoteServerMsgId = quoteServerMsgId
    message.quoteText = quoteText
    return await this.send(message)
  }

  /** Explicit user retry for a failed/interrupted durable outbox item. */
  async retryMessage(clientMsgId: string): Promise<void> {
    await this.store.retry(clientMsgId)
    this.listeners.forEach((listener: PteIMListener) => listener.onMessageStateChanged(clientMsgId, PteIMSendState.PENDING))
    await this.flushOutbox()
  }

  /** Removes only the current device copy. Remote deletion/revoke remains server-authoritative. */
  async deleteLocalMessage(clientMsgId: string): Promise<void> {
    await this.store.removeMessage(clientMsgId)
  }

  /** Globally recalls the caller's own message through the IM service. */
  async recallMessage(message: PteIMMessage): Promise<void> {
    if (message.serverMsgId.length === 0) throw new Error('message must be sent before recall')
    const body = new PteIMRequestBody(); body.messageId = message.serverMsgId
    await this.sdkRequest('/v1/im/messages/recall', body)
  }

  /** Hides a message only for this IM account after durable server confirmation. */
  async deleteMessage(message: PteIMMessage): Promise<void> {
    if (message.serverMsgId.length === 0) throw new Error('message must be sent before delete')
    const body = new PteIMRequestBody(); body.messageId = message.serverMsgId
    await this.sdkRequest('/v1/im/messages/delete', body)
    await this.store.removeMessage(message.clientMsgId)
  }

  async addMessageReaction(message: PteIMMessage, emoji: string): Promise<WireObject> { return await this.changeMessageReaction(message, emoji, true) }
  async removeMessageReaction(message: PteIMMessage, emoji: string): Promise<WireObject> { return await this.changeMessageReaction(message, emoji, false) }
  private async changeMessageReaction(message: PteIMMessage, emoji: string, add: boolean): Promise<WireObject> {
    if (message.serverMsgId.length === 0 || emoji.trim().length === 0) throw new Error('message and emoji are required')
    const body = new PteIMRequestBody(); body.messageId = message.serverMsgId; body.emoji = emoji
    return await this.sdkRequest(add ? '/v1/im/messages/reactions/add' : '/v1/im/messages/reactions/remove', body)
  }

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
  async syncStateNow(): Promise<void> {
    try {
      const page = await this.syncState(await this.store.stateCursor(), 100)
      await this.store.setStateCursor(page.nextCursor)
      this.listeners.forEach((listener: PteIMListener) => listener.onStateChanges(page.changes))
      if (page.hasMore) await this.syncStateNow()
    } catch (error) { this.emitError(error) }
  }
  /** Pulls all cursor pages and persists the compact conversation summary cache in encrypted RDB. */
  async syncConversationsNow(): Promise<void> {
    if (this.conversationSyncing) return
    this.conversationSyncing = true
    try {
      const body = new PteIMRequestBody(); body.cursor = await this.store.conversationCursor(); body.limit = 100
      const payload = await this.sdkRequest('/v1/im/conversations/cursor', body)
      const raw = payload['list'] as Object[]
      const values: PteIMRemoteConversation[] = raw === undefined || raw === null ? [] : raw.map((item: Object) => this.remoteConversation(item as WireObject))
      await this.store.applyRemoteConversations(values, this.stringValue(payload, 'nextCursor'))
      if (this.boolValue(payload, 'hasMore')) {
        this.conversationSyncing = false
        await this.syncConversationsNow()
      }
    } catch (error) { this.emitError(error) }
    finally { this.conversationSyncing = false }
  }

  async localMessages(conversationId: string, beforeCreatedAt: number = 0, limit: number = 50): Promise<PteIMMessage[]> {
    const stored = await this.store.localMessages(conversationId, beforeCreatedAt, limit)
    return stored.map((row) => this.messageFromJson(row.payload, row.serverMsgId, row.serverSeq, row.createdAt, row.state))
  }

  async localConversations(limit: number = 100): Promise<PteIMConversation[]> {
    const stored = await this.store.localConversations(limit)
    return stored.map((row) => new PteIMConversation(row.conversationId, this.messageFromJson(row.stored.payload, row.stored.serverMsgId, row.stored.serverSeq, row.stored.createdAt, row.stored.state), row.stored.createdAt))
  }

  /** Reads cursor-synced server conversation metadata from the encrypted local RDB cache. */
  async localRemoteConversations(limit: number = 100): Promise<PteIMRemoteConversation[]> {
    const stored = await this.store.localRemoteConversations(limit)
    return stored.map((row: PteIMStoredRemoteConversation) => this.remoteConversation(JSON.parse(row.payload) as WireObject))
  }

  async fetchConversationPage(page: number = 1, pageSize: number = 50): Promise<PteIMConversationPage> {
    if (page <= 0 || pageSize <= 0 || pageSize > 200) throw new Error('invalid conversation page')
    const body = new PteIMRequestBody(); body.page = page; body.pageSize = pageSize
    const data = await this.sdkRequest('/v1/im/conversations', body)
    const values = data['list'] as Object[]
    const items: PteIMRemoteConversation[] = values === undefined || values === null ? [] : values.map((value: Object) => this.remoteConversation(value as WireObject))
    return new PteIMConversationPage(this.numberValue(data, 'total'), items)
  }

  async fetchMyProfile(): Promise<PteIMUserProfile> {
    return this.userProfile(await this.sdkRequest('/v1/im/profile/me', new PteIMRequestBody()))
  }

  /** The UserSig identity chooses the owner; update always has exactly one field. */
  async updateMyProfile(update: PteIMUserProfileUpdate): Promise<PteIMUserProfile> {
    const body = new PteIMRequestBody(); body.field = update.field; body.value = update.value
    return this.userProfile(await this.sdkRequest('/v1/im/profile/update', body))
  }
  async fetchFriends(cursor: string = '', limit: number = 50): Promise<PteIMContactPage> { return await this.contactPage('/v1/im/friends', cursor, limit) }
  async fetchFollows(cursor: string = '', limit: number = 50): Promise<PteIMContactPage> { return await this.contactPage('/v1/im/follows', cursor, limit) }
  async follow(userId: number, remark: string = ''): Promise<void> { await this.contactAction('/v1/im/follows/follow', userId, remark) }
  async unfollow(userId: number): Promise<void> { await this.contactAction('/v1/im/follows/unfollow', userId) }
  async block(userId: number): Promise<void> { await this.contactAction('/v1/im/blocks/add', userId) }
  async unblock(userId: number): Promise<void> { await this.contactAction('/v1/im/blocks/remove', userId) }
  async fetchGroups(cursor: string = '', limit: number = 50): Promise<PteIMGroupPage> { const body = new PteIMRequestBody(); body.cursor = cursor; body.limit = limit; const data = await this.sdkRequest('/v1/im/groups', body); const out = new PteIMGroupPage(); out.nextCursor = this.stringValue(data, 'nextCursor'); out.hasMore = this.boolValue(data, 'hasMore'); const values = data['list'] as Object[]; if (values) out.list = values.map((v: Object) => this.remoteConversation(v as WireObject)); return out }
  async fetchGroupMembers(conversationId: number, cursor: string = '', limit: number = 50): Promise<PteIMMemberPage> { const body = new PteIMRequestBody(); body.conversationId = conversationId; body.cursor = cursor; body.limit = limit; const data = await this.sdkRequest('/v1/im/groups/members', body); const out = new PteIMMemberPage(); out.nextCursor = this.stringValue(data, 'nextCursor'); out.hasMore = this.boolValue(data, 'hasMore'); const values = data['list'] as Object[]; if (values) out.list = values.map((v: Object) => { const x = v as WireObject; const m = new PteIMMember(); m.userId = this.numberValue(x, 'user_id'); m.role = this.numberValue(x, 'role'); m.alias = this.stringValue(x, 'alias'); m.muteUntil = this.numberValue(x, 'mute_until'); m.joinedAt = this.numberValue(x, 'joined_at'); return m }); return out }
  async joinGroup(conversationId: number): Promise<void> { const body = new PteIMRequestBody(); body.conversationId = conversationId; await this.sdkRequest('/v1/im/groups/join', body) }
  async inviteGroupMembers(conversationId: number, memberIds: number[]): Promise<void> { if (conversationId <= 0 || memberIds.length === 0 || memberIds.some((id: number): boolean => id <= 0)) throw new Error('invalid group members'); const body = new PteIMRequestBody(); body.conversationId = conversationId; body.memberIds = memberIds; await this.sdkRequest('/v1/im/groups/members/invite', body) }
  async removeGroupMember(conversationId: number, memberId: number): Promise<void> { if (conversationId <= 0 || memberId <= 0) throw new Error('invalid group member'); const body = new PteIMRequestBody(); body.conversationId = conversationId; body.memberId = memberId; await this.sdkRequest('/v1/im/groups/members/remove', body) }
  async leaveGroup(conversationId: number): Promise<void> { if (conversationId <= 0) throw new Error('invalid group'); const body = new PteIMRequestBody(); body.conversationId = conversationId; await this.sdkRequest('/v1/im/groups/leave', body) }
  /** Stores only a server-side AES-GCM encrypted provider token. */
  async registerPushDevice(deviceId: string, platform: PteIMPushPlatform, token: string, notificationEnabled: boolean = true): Promise<PteIMPushDevice> { if (deviceId.length < 8 || token.length < 16) throw new Error('invalid push device'); const body = new PteIMRequestBody(); body.deviceId = deviceId; body.platform = platform; body.token = token; body.notificationEnabled = notificationEnabled; return this.pushDevice(await this.sdkRequest('/v1/im/push/devices/register', body)) }
  async setPushDeviceNotification(deviceId: string, platform: PteIMPushPlatform, enabled: boolean): Promise<PteIMPushDevice> { if (deviceId.length < 8) throw new Error('invalid push device'); const body = new PteIMRequestBody(); body.deviceId = deviceId; body.platform = platform; body.notificationEnabled = enabled; return this.pushDevice(await this.sdkRequest('/v1/im/push/devices/notification', body)) }
  async unregisterPushDevice(deviceId: string, platform: PteIMPushPlatform): Promise<void> { if (deviceId.length < 8) throw new Error('invalid push device'); const body = new PteIMRequestBody(); body.deviceId = deviceId; body.platform = platform; await this.sdkRequest('/v1/im/push/devices/unregister', body) }
  async syncState(cursor: string = '', limit: number = 100): Promise<PteIMStateChangePage> { const body = new PteIMRequestBody(); body.cursor = cursor; body.limit = limit; const data = await this.sdkRequest('/v1/im/state/sync', body); const out = new PteIMStateChangePage(); out.nextCursor = this.stringValue(data, 'nextCursor'); out.hasMore = this.boolValue(data, 'hasMore'); const values = data['changes'] as Object[]; if (values) out.changes = values.map((v: Object) => { const x = v as WireObject; const c = new PteIMStateChange(); c.id = this.stringValue(x, 'id'); c.entityType = this.stringValue(x, 'entityType'); c.entityId = this.stringValue(x, 'entityId'); c.operation = this.stringValue(x, 'operation'); c.createdAt = this.numberValue(x, 'createdAt'); return c }); return out }
  async fetchDefaultSetting(): Promise<PteIMDefaultSetting> { const data = await this.sdkRequest('/v1/im/settings/default', new PteIMRequestBody()); const out = new PteIMDefaultSetting(); out.chatPrerequisite = this.stringValue(data, 'chatPrerequisite'); out.notificationEnabled = this.boolValue(data, 'notificationEnabled'); out.groupJoinMode = this.stringValue(data, 'groupJoinMode'); return out }

  async openSingleConversation(peerUserId: number): Promise<PteIMRemoteConversation> {
    if (peerUserId <= 0) throw new Error('peerUserId must be positive')
    // Plain object: ArkTS JSON.stringify on class instances can omit fields.
    const body: WireObject = { 'peerUserId': peerUserId }
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

  private async contactPage(path: string, cursor: string, limit: number): Promise<PteIMContactPage> { const body = new PteIMRequestBody(); body.cursor = cursor; body.limit = limit; const data = await this.sdkRequest(path, body); const out = new PteIMContactPage(); out.nextCursor = this.stringValue(data, 'nextCursor'); out.hasMore = this.boolValue(data, 'hasMore'); const values = data['list'] as Object[]; if (values) out.list = values.map((v: Object) => { const x = v as WireObject; const c = new PteIMContact(); c.userId = this.stringValue(x, 'userId'); c.remark = this.stringValue(x, 'remark'); c.nickname = this.stringValue(x, 'nickname'); c.avatar = this.stringValue(x, 'avatar'); c.gender = this.stringValue(x, 'gender') as PteIMGender; c.followedAt = this.numberValue(x, 'followedAt'); return c }); return out }
  private async contactAction(path: string, userId: number, remark: string = ''): Promise<void> { if (userId <= 0) throw new Error('userId must be positive'); const body = new PteIMRequestBody(); body.targetUserId = userId; body.remark = remark; await this.sdkRequest(path, body) }

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
    try {
      const bytes = this.readFile(filePath)
      const body = new PteIMRequestBody(); body.mediaType = type; body.contentType = mimeType; body.contentLength = bytes.byteLength
      const credential = await this.apiImRequest('/v1/im/media/put-url', body)
      const key = this.stringValue(credential, 'key')
      const uploadUrl = this.stringValue(credential, 'uploadUrl')
      const headers = credential['headers'] as WireObject
      if (key.length === 0 || uploadUrl.length === 0 || headers === undefined || headers === null) throw new Error('media credential response is invalid')
      const request = http.createHttp()
      try {
      const requestHeaders: Record<string, string> = {}
      requestHeaders['Content-Type'] = this.stringValue(headers, 'Content-Type')
      const options: PteIMHttpRequestOptions = {
        method: http.RequestMethod.PUT,
        header: requestHeaders,
        extraData: bytes.buffer,
        connectTimeout: 10000,
        readTimeout: 30000,
      }
      const response = await request.request(uploadUrl, options)
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`COS upload failed with HTTP ${response.responseCode}`)
      return new PteIMMedia(key, '', '', 0, 0, 0, bytes.byteLength, this.fileName(filePath, type), mimeType)
      } finally { request.destroy() }
    } catch (error) { throw new Error(`PteIM COS media upload failed: ${String(error)}`) }
  }

  private readFile(filePath: string): Uint8Array {
    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      const size = fileIo.statSync(file.fd).size
      if (size <= 0) throw new Error('media file is empty')
      const buffer = new ArrayBuffer(size)
      const read = fileIo.readSync(file.fd, buffer)
      if (read !== size) throw new Error('could not read the complete media file')
      return new Uint8Array(buffer)
    } catch (error) { throw new Error(`PteIM media file read failed: ${String(error)}`) }
    finally {
      if (file !== null) {
        try { fileIo.closeSync(file) }
        catch (error) { throw new Error(`PteIM media file close failed: ${String(error)}`) }
      }
    }
  }

  private fileName(filePath: string, type: PteIMMessageType): string {
    const parts = filePath.split('/')
    const name = parts.length > 0 ? parts[parts.length - 1] : ''
    return name.length > 0 ? name.replace(/"/g, '') : `media-${type === PteIMMessageType.IMAGE ? 'image' : type === PteIMMessageType.VIDEO ? 'video' : 'file'}`
  }

  private connect(): void {
    this.socket = webSocket.createWebSocket()
    this.socket.on('open', () => { this.onOpen() })
    this.socket.on('message', (_error: Error | null, value: string | ArrayBuffer) => {
      if (typeof value === 'string') void this.handleInbound(value)
      else void this.handleInbound(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(value)))
    })
    this.socket.on('close', () => { this.onClose() })
    this.socket.on('error', (error: Error) => { this.emitError(error); this.onClose() })
    // OpenHarmony connect success callback often passes `undefined` (not null).
    // Treat only truthy values as failure — `undefined !== null` used to crash emitError.
    const headers: Record<string, string> = {}
    const origin = this.webSocketOrigin()
    if (origin.length > 0) headers['Origin'] = origin
    this.socket.connect(this.webSocketURL(), { header: headers }, (error: Error) => {
      if (error) {
        this.emitError(error)
        this.onClose()
      }
    })
  }

  // The configured IM service validates UserSig at WSS upgrade; use the same query contract as H5/mini-program.
  private webSocketURL(): string {
    const separator = this.base.imDomain.indexOf('?') >= 0 ? '&' : '?'
    return this.base.imDomain + separator + 'sdkAppID=' + encodeURIComponent(this.config.sdkAppId.toString()) +
      '&identifier=' + encodeURIComponent(this.config.userId) + '&userSig=' + encodeURIComponent(this.config.userSig)
  }

  /** Returns an RFC 6454 origin derived from the configured API base URL. */
  private webSocketOrigin(): string {
    const match = this.base.apiDomain.match(/^(https?:\/\/[^/]+)/i)
    return match === null ? '' : match[1]
  }

  private async onOpen(): Promise<void> {
    this.reconnectAttempt = 0
    this.connected = true
    this.listeners.forEach((listener: PteIMListener) => listener.onConnectionChanged(true))
    const body = new PteIMRequestBody(); body.syncCursor = await this.store.cursor()
    this.sendEnvelope('login', body)
    await this.flushOutbox()
    await this.syncNow()
    await this.syncStateNow()
    await this.syncConversationsNow()
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
      } else if (action === 'message_event') {
        await this.handleMessageEvent(payload)
      } else if (action === 'user_sig_will_expire' || action === 'user_sig_expired') { void this.refreshUserSig(true) }
      else if (action === 'sync_required') this.syncNow()
    } catch (error) { this.emitError(error) }
  }

  private async handleMessageEvent(payload: WireObject): Promise<void> {
    const serverMsgId = this.stringValue(payload, 'serverMsgId')
    const eventType = this.stringValue(payload, 'eventType')
    if (serverMsgId.length === 0 || eventType.length === 0) return
    if (eventType === 'chat.message.deleted') {
      await this.store.removeMessageByServerMsgId(serverMsgId)
      return
    }
    const stored = await this.store.loadByServerMsgId(serverMsgId)
    if (stored === null) return
    const wire = JSON.parse(stored.payload) as WireObject
    if (eventType === 'chat.message.recalled') {
      wire['status'] = this.numberValue(payload, 'status') > 0 ? this.numberValue(payload, 'status') : 2
      wire['recalledAt'] = this.numberValue(payload, 'recalledAt') > 0 ? this.numberValue(payload, 'recalledAt') : Date.now()
    } else if (eventType === 'chat.message.reaction_changed') {
      const emoji = this.stringValue(payload, 'emoji')
      if (emoji.length === 0) return
      const added = this.stringValue(payload, 'reactionAction') === 'added'
      const actor = this.stringValue(payload, 'userId')
      const raw = wire['reactions']
      const list: Object[] = Array.isArray(raw) ? raw as Object[] : []
      const next: Object[] = []
      let found = false
      for (let i = 0; i < list.length; i++) {
        const item = list[i] as WireObject
        const itemEmoji = this.stringValue(item, 'emoji')
        if (itemEmoji !== emoji) {
          next.push(item)
          continue
        }
        found = true
        const count = this.numberValue(item, 'count') + (added ? 1 : -1)
        const reactedByMe = actor === this.config.userId ? added : this.boolValue(item, 'reactedByMe')
        if (count > 0) {
          const row: WireObject = { 'emoji': emoji, 'count': Math.max(0, count), 'reactedByMe': reactedByMe }
          next.push(row)
        }
      }
      if (!found && added) {
        const row: WireObject = { 'emoji': emoji, 'count': 1, 'reactedByMe': actor === this.config.userId }
        next.push(row)
      }
      wire['reactions'] = next
    } else {
      return
    }
    await this.store.writePayloadByServerMsgId(serverMsgId, JSON.stringify(wire))
    const updated = this.messageFromJson(JSON.stringify(wire), stored.serverMsgId, stored.serverSeq, stored.createdAt, stored.state)
    this.listeners.forEach((listener: PteIMListener) => listener.onMessageUpdated(updated))
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
    // OpenHarmony reports a successful send with undefined, not null.
    this.socket.send(JSON.stringify(envelope), (error: Error) => { if (error) this.emitError(error) })
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
          clientMsgId: message.clientMsgId, conversationId: message.conversationId, type: message.type, e2ee, quoteMessageId: message.quoteServerMsgId,
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

  private scheduleUserSigRefresh(): void {
    if (this.userSigRefreshTimer >= 0) clearTimeout(this.userSigRefreshTimer)
    this.userSigRefreshTimer = -1
    if (this.stopped || this.config.userSigProvider === null || this.config.userSigExpireAt <= 0) return
    const delay = Math.max(1000, this.config.userSigExpireAt * 1000 - Date.now() - 300000)
    this.userSigRefreshTimer = setTimeout(() => { this.userSigRefreshTimer = -1; void this.refreshUserSig(true) }, delay)
  }

  private cancelTimers(): void {
    if (this.reconnectTimer >= 0) clearTimeout(this.reconnectTimer)
    if (this.outboxTimer >= 0) clearTimeout(this.outboxTimer)
    if (this.userSigRefreshTimer >= 0) clearTimeout(this.userSigRefreshTimer)
    this.reconnectTimer = -1; this.outboxTimer = -1; this.userSigRefreshTimer = -1
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
      // OpenHarmony http.header must be a plain Record; Map drops custom headers
      // (e.g. X-Pte-Response-Public-Key) and api-im then returns HTTP 400.
      const responseKey = await PteIMResponseCrypto.createRequestKey()
      const requestHeaders = this.apiRequestHeaders()
      requestHeaders['X-Pte-Response-Public-Key'] = responseKey.publicKey
      const options: PteIMHttpRequestOptions = { method: http.RequestMethod.POST, header: requestHeaders, extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000 }
      const response = await request.request(`${this.base.apiDomain.replace(/\/$/, '')}${path}`, options)
      if (response.responseCode === 401) void this.refreshUserSig(true)
      if (response.responseCode < 200 || response.responseCode >= 300) {
        let detail = ''
        try { detail = response.result !== undefined && response.result !== null ? response.result.toString() : '' } catch (_e) { detail = '' }
        throw new Error(`IM API failed with HTTP ${response.responseCode}${detail.length > 0 ? `: ${detail}` : ''}`)
      }
      const root = await PteIMResponseCrypto.decryptResponse(JSON.parse(response.result.toString()) as WireObject, responseKey)
      if (this.numberValue(root, 'code') !== 1) throw new Error(this.stringValue(root, 'msg'))
      return root['data'] as WireObject
    } catch (error) { throw new Error(`PteIM encrypted API request failed (${path}): ${String(error)}`) }
    finally { request.destroy() }
  }
  private async apiImRequest(path: string, body: PteIMRequestBody): Promise<WireObject> {
    const request = http.createHttp()
    try {
      const requestHeaders = this.apiRequestHeaders()
      const options: PteIMHttpRequestOptions = { method: http.RequestMethod.POST, header: requestHeaders, extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000 }
      const response = await request.request(`${this.base.apiDomain.replace(/\/$/, '')}${path}`, options)
      if (response.responseCode === 401) void this.refreshUserSig(true)
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`IM API failed with HTTP ${response.responseCode}`)
      const root = JSON.parse(response.result.toString()) as WireObject
      if (this.numberValue(root, 'code') !== 0) throw new Error(this.stringValue(root, 'msg'))
      return root['data'] as WireObject
    } catch (error) { throw new Error(`PteIM API request failed (${path}): ${String(error)}`) }
    finally { request.destroy() }
  }
  async commerceRequest(path: string, body: WireObject): Promise<WireObject> {
    if (this.base.commerceDomain.length === 0) throw new Error('commerceDomain is not configured')
    const request = http.createHttp()
    try {
      const options: PteIMHttpRequestOptions = { method: http.RequestMethod.POST, header: this.apiRequestHeaders(), extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000 }
      const response = await request.request(`${this.base.commerceDomain.replace(/\/$/, '')}${path}`, options)
      if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`Commerce failed with HTTP ${response.responseCode}`)
      const root = JSON.parse(response.result.toString()) as WireObject
      if (this.numberValue(root, 'code') !== 1) throw new Error(this.stringValue(root, 'msg'))
      return root['data'] as WireObject
    } finally { request.destroy() }
  }
  private remoteConversation(value: WireObject): PteIMRemoteConversation { return new PteIMRemoteConversation(this.numberValue(value, 'id'), this.stringValue(value, 'type'), this.stringValue(value, 'title'), this.stringValue(value, 'avatar'), this.numberValue(value, 'last_message_seq'), this.stringValue(value, 'last_message_snapshot'), this.numberValue(value, 'last_message_at'), this.numberValue(value, 'unread_count')) }
  private pushDevice(value: WireObject): PteIMPushDevice { const out = new PteIMPushDevice(); out.deviceId = this.stringValue(value, 'deviceId'); const platform = this.stringValue(value, 'platform'); out.platform = platform === 'android' ? PteIMPushPlatform.ANDROID : platform === 'ios' ? PteIMPushPlatform.IOS : platform === 'web' ? PteIMPushPlatform.WEB : platform === 'wechat' ? PteIMPushPlatform.WECHAT : PteIMPushPlatform.HARMONY; out.notificationEnabled = this.boolValue(value, 'notificationEnabled'); out.lastSeenAt = this.numberValue(value, 'lastSeenAt'); return out }
  private userProfile(value: WireObject): PteIMUserProfile {
    const rawGender = this.stringValue(value, 'gender')
    const gender = rawGender === 'male' ? PteIMGender.MALE : rawGender === 'female' ? PteIMGender.FEMALE : PteIMGender.UNKNOWN
    return new PteIMUserProfile(this.numberValue(value, 'user_id'), this.stringValue(value, 'nickname'), this.stringValue(value, 'avatar'), gender, this.stringValue(value, 'birthday'), this.stringValue(value, 'province'), this.stringValue(value, 'city'), this.stringValue(value, 'district'))
  }
  private remoteMessage(value: WireObject): PteIMRemoteMessage { return new PteIMRemoteMessage(this.numberValue(value, 'message_id'), this.numberValue(value, 'conversation_id'), this.numberValue(value, 'sender_id'), this.stringValue(value, 'client_msg_id'), this.stringValue(value, 'msg_type'), this.stringValue(value, 'content'), this.stringValue(value, 'payload'), this.numberValue(value, 'seq'), this.numberValue(value, 'sent_at'), this.numberValue(value, 'recalled_at')) }
  private apiRequestHeaders(): Record<string, string> {
    const headers: Record<string, string> = {}
    headers['Content-Type'] = 'application/json'
    headers['Authorization'] = `Bearer ${this.config.userSig}`
    headers['X-Pte-Sdk-AppId'] = this.config.sdkAppId.toString()
    headers['X-Pte-User-Id'] = this.config.userId
    return headers
  }
  private resolveCosUrl(value: string): string { return value.length === 0 || value.startsWith('https://') ? value : `${this.base.cosDomain.replace(/\/$/, '')}/${value.replace(/^\//, '')}` }
  private emitError(error: Object | Error | string | null | undefined): void {
    let value: Error
    if (error instanceof Error) {
      value = error
    } else if (error === null || error === undefined) {
      value = new Error('unknown IM error')
    } else {
      value = new Error(String(error))
    }
    this.listeners.forEach((listener: PteIMListener) => {
      try {
        listener.onError(value)
      } catch (_e) {
        // listener must not crash the process
      }
    })
  }

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
    const media = type === PteIMMessageType.IMAGE || type === PteIMMessageType.VIDEO || type === PteIMMessageType.FILE ? new PteIMMedia(this.resolveCosUrl(this.stringValue(content, 'url')), this.resolveCosUrl(this.stringValue(content, 'thumbnailUrl')), this.resolveCosUrl(this.stringValue(content, 'coverUrl')), this.numberValue(content, 'width'), this.numberValue(content, 'height'), this.numberValue(content, 'durationMs'), this.numberValue(content, 'sizeBytes'), this.stringValue(content, 'fileName'), this.stringValue(content, 'mimeType')) : null
    const voice = type === PteIMMessageType.VOICE ? new PteIMVoice(this.resolveCosUrl(this.stringValue(content, 'url')), this.numberValue(content, 'durationMs'), this.stringValue(content, 'waveform'), this.numberValue(content, 'sizeBytes')) : null
    const location = type === PteIMMessageType.LOCATION ? new PteIMLocation(this.numberValue(content, 'latitude'), this.numberValue(content, 'longitude'), this.stringValue(content, 'name'), this.stringValue(content, 'address')) : null
    const business = type === PteIMMessageType.GIFT || type === PteIMMessageType.RED_PACKET || type === PteIMMessageType.ORDER || type === PteIMMessageType.CUSTOM ? new PteIMBusinessContent(this.stringValue(content, 'businessId'), this.stringValue(content, 'title'), this.stringValue(content, 'subtitle'), this.stringValue(content, 'actionUrl')) : null
    const message = new PteIMMessage(this.stringValue(value, 'conversationId'), type, this.stringValue(content, 'text'), this.stringValue(content, 'packageId'), this.stringValue(content, 'emojiId'), media, voice, location, business, this.stringValue(value, 'clientMsgId'), this.numberValue(value, 'createdAt'), PteIMSendState.SENT)
    message.senderId = this.stringValue(value, 'senderId')
    message.serverMsgId = this.stringValue(value, 'serverMsgId'); message.serverSeq = this.numberValue(value, 'serverSeq')
    message.quoteClientMsgId = this.stringValue(content, 'quoteClientMsgId')
    message.quoteServerMsgId = this.stringValue(content, 'quoteServerMsgId') || this.stringValue(value, 'quoteMessageId')
    message.quoteText = this.stringValue(content, 'quoteText')
    message.status = this.numberValue(value, 'status') > 0 ? this.numberValue(value, 'status') : 1
    message.recalledAt = this.numberValue(value, 'recalledAt')
    const reactionsRaw = value['reactions']
    if (Array.isArray(reactionsRaw)) {
      const reactions: PteIMMessageReaction[] = []
      for (let i = 0; i < reactionsRaw.length; i++) {
        const row = reactionsRaw[i] as WireObject
        const emoji = this.stringValue(row, 'emoji')
        if (emoji.length === 0) continue
        reactions.push(new PteIMMessageReaction(emoji, this.numberValue(row, 'count'), this.boolValue(row, 'reactedByMe') || this.boolValue(row, 'reacted_by_me')))
      }
      message.reactions = reactions
    }
    return message
  }
  private async messageFromRemoteWire(value: WireObject): Promise<PteIMMessage> {
    const e2ee = value['e2ee'] as WireObject
    if (e2ee === undefined || e2ee === null) return this.messageFromWire(value)
    if (!(await this.e2ee.canDecrypt(e2ee))) {
      const unavailableContent = new PteIMWireContent()
      unavailableContent.text = 'E2EE message unavailable on this device'
      const unavailable: PteIMDecryptedMessage = {
        clientMsgId: value['clientMsgId'], serverMsgId: value['serverMsgId'], serverSeq: value['serverSeq'],
        conversationId: value['conversationId'], senderId: value['senderId'], type: 'text', createdAt: value['createdAt'],
        content: unavailableContent,
      }
      return this.messageFromWire(unavailable)
    }
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

/** Commerce namespace; callers pass the same contract used by Android/iOS. */
export class PteIMCommerce {
  private sdk: PteIMSDK
  constructor(sdk: PteIMSDK) { this.sdk = sdk }
  capabilities(): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/capabilities', {}) }
  gifts(): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/gifts', {}) }
  wallet(): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/wallet', {}) }
  backpack(): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/backpack', {}) }
  orders(limit: number = 50): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/orders', { 'limit': limit }) }
  sendGift(request: WireObject): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/gifts/send', request) }
  useBackpack(request: WireObject): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/backpack/use', request) }
  createRedPacket(request: WireObject): Promise<WireObject> { return this.sdk.commerceRequest('/v1/commerce/red-packets/create', request) }
  redPacket(id: string): Promise<WireObject> { return this.sdk.commerceRequest(`/v1/commerce/red-packets/${id}`, {}) }
  claimRedPacket(id: string): Promise<WireObject> { return this.sdk.commerceRequest(`/v1/commerce/red-packets/${id}/claim`, {}) }
}

export class PteIMSDKBootstrap {
  private context: Context
  private baseConfig: PteIMBaseConfig
  constructor(context: Context, baseConfig: PteIMBaseConfig) { this.context = context; this.baseConfig = baseConfig }

  /**
   * Creates a client. Set autoStart to false when the caller needs to register
   * listeners before network activity begins (for example, an acceptance host).
   */
  async login(loginConfig: PteIMLoginConfig, autoStart: boolean = true): Promise<PteIMSDK> {
    this.baseConfig.validate(); loginConfig.validate()
    const storeName = `pte_live_im_${loginConfig.sdkAppId}_${loginConfig.userId.replace(/[^A-Za-z0-9_]/g, '_')}`
    const client = new PteIMSDK(loginConfig, this.baseConfig, await PteIMRdbStore.open(this.context, storeName))
    if (autoStart) client.start()
    return client
  }
}
