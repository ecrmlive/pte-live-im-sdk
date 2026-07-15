/** Configuration that is shared by the application. Configure it before login. */
export enum PteIMThemeMode { SYSTEM = 'system', LIGHT = 'light', DARK = 'dark' }
export enum PteIMLanguage { SYSTEM = 'system', ZH_CN = 'zh-CN', EN_US = 'en-US' }
export enum PteIMMessageType {
  TEXT = 'text', EMOJI = 'emoji', IMAGE = 'image', VIDEO = 'video', VOICE = 'voice',
  LOCATION = 'location', GIFT = 'gift', RED_PACKET = 'red_packet', ORDER = 'order'
}
export enum PteIMSendState { PENDING = 'pending', UPLOADING = 'uploading', SENT = 'sent', FAILED = 'failed' }

/** Explicit wire models keep API 23 ArkTS serialization type-safe. */
export class PteIMWireContent {
  text: string = ''
  packageId: string = ''
  emojiId: string = ''
  url: string = ''
  thumbnailUrl: string = ''
  coverUrl: string = ''
  width: number = 0
  height: number = 0
  durationMs: number = 0
  sizeBytes: number = 0
  waveform: string = ''
  latitude: number = 0
  longitude: number = 0
  name: string = ''
  address: string = ''
  businessId: string = ''
  title: string = ''
  subtitle: string = ''
  actionUrl: string = ''
}

export class PteIMWireMessage {
  clientMsgId: string = ''
  serverMsgId: string = ''
  serverSeq: number = 0
  conversationId: string = ''
  type: string = ''
  createdAt: number = 0
  content: PteIMWireContent = new PteIMWireContent()
}

export class PteIMBaseConfig {
  apiDomain: string
  imDomain: string
  cosDomain: string
  themeMode: PteIMThemeMode
  language: PteIMLanguage

  constructor(apiDomain: string, imDomain: string, cosDomain: string,
    themeMode: PteIMThemeMode = PteIMThemeMode.SYSTEM, language: PteIMLanguage = PteIMLanguage.SYSTEM) {
    this.apiDomain = apiDomain
    this.imDomain = imDomain
    this.cosDomain = cosDomain
    this.themeMode = themeMode
    this.language = language
  }

  validate(): void {
    if (!this.apiDomain.startsWith('https://')) throw new Error('apiDomain must be an HTTPS origin')
    if (!this.imDomain.startsWith('wss://') || !this.imDomain.endsWith('/ws')) throw new Error('imDomain must be a WSS URL ending in /ws')
    if (!this.cosDomain.startsWith('https://')) throw new Error('cosDomain must be an HTTPS origin')
  }
}

export class PteIMLoginConfig {
  sdkAppId: number
  userId: string
  userSig: string

  constructor(sdkAppId: number, userId: string, userSig: string) {
    this.sdkAppId = sdkAppId
    this.userId = userId
    this.userSig = userSig
  }

  validate(): void {
    if (this.sdkAppId <= 0) throw new Error('sdkAppId must be positive')
    if (!/^[1-9][0-9]*$/.test(this.userId)) throw new Error('userId must be a positive numeric string')
    if (this.userSig.length === 0) throw new Error('userSig is required')
  }
}

export class PteIMAppearance {
  themeMode: PteIMThemeMode
  language: PteIMLanguage

  constructor(themeMode: PteIMThemeMode, language: PteIMLanguage) {
    this.themeMode = themeMode
    this.language = language
  }
}
export class PteIMMedia {
  url: string
  thumbnailUrl: string
  coverUrl: string
  width: number
  height: number
  durationMs: number
  sizeBytes: number

  constructor(url: string = '', thumbnailUrl: string = '', coverUrl: string = '',
    width: number = 0, height: number = 0, durationMs: number = 0, sizeBytes: number = 0) {
    this.url = url
    this.thumbnailUrl = thumbnailUrl
    this.coverUrl = coverUrl
    this.width = width
    this.height = height
    this.durationMs = durationMs
    this.sizeBytes = sizeBytes
  }
}
export class PteIMVoice {
  url: string
  durationMs: number
  waveform: string
  sizeBytes: number

  constructor(url: string, durationMs: number, waveform: string = '', sizeBytes: number = 0) {
    this.url = url
    this.durationMs = durationMs
    this.waveform = waveform
    this.sizeBytes = sizeBytes
  }
}
export class PteIMLocation {
  latitude: number
  longitude: number
  name: string
  address: string

  constructor(latitude: number, longitude: number, name: string, address: string = '') {
    this.latitude = latitude
    this.longitude = longitude
    this.name = name
    this.address = address
  }
}
export class PteIMBusinessContent {
  businessId: string
  title: string
  subtitle: string
  actionUrl: string

  constructor(businessId: string, title: string, subtitle: string = '', actionUrl: string = '') {
    this.businessId = businessId
    this.title = title
    this.subtitle = subtitle
    this.actionUrl = actionUrl
  }
}

export class PteIMMessage {
  conversationId: string
  type: PteIMMessageType
  text: string
  packageId: string
  emojiId: string
  media: PteIMMedia | null
  voice: PteIMVoice | null
  location: PteIMLocation | null
  business: PteIMBusinessContent | null
  clientMsgId: string
  serverMsgId: string = ''
  serverSeq: number = 0
  createdAt: number
  state: PteIMSendState

  constructor(conversationId: string, type: PteIMMessageType, text: string = '',
    packageId: string = '', emojiId: string = '', media: PteIMMedia | null = null,
    voice: PteIMVoice | null = null, location: PteIMLocation | null = null,
    business: PteIMBusinessContent | null = null, clientMsgId: string = '', createdAt: number = 0,
    state: PteIMSendState = PteIMSendState.PENDING) {
    this.conversationId = conversationId
    this.type = type
    this.text = text
    this.packageId = packageId
    this.emojiId = emojiId
    this.media = media
    this.voice = voice
    this.location = location
    this.business = business
    this.clientMsgId = clientMsgId.length > 0 ? clientMsgId : PteIMMessage.newClientMsgId()
    this.createdAt = createdAt > 0 ? createdAt : Date.now()
    this.state = state
  }

  private static newClientMsgId(): string {
    return `${Date.now()}-${Math.floor(Math.random() * 1000000000)}`
  }

  toWire(): PteIMWireMessage {
    const content = new PteIMWireContent()
    content.text = this.text
    content.packageId = this.packageId
    content.emojiId = this.emojiId
    if (this.media !== null) {
      content.url = this.media.url; content.thumbnailUrl = this.media.thumbnailUrl; content.coverUrl = this.media.coverUrl
      content.width = this.media.width; content.height = this.media.height; content.durationMs = this.media.durationMs; content.sizeBytes = this.media.sizeBytes
    }
    if (this.voice !== null) {
      content.url = this.voice.url; content.durationMs = this.voice.durationMs; content.waveform = this.voice.waveform; content.sizeBytes = this.voice.sizeBytes
    }
    if (this.location !== null) {
      content.latitude = this.location.latitude; content.longitude = this.location.longitude; content.name = this.location.name; content.address = this.location.address
    }
    if (this.business !== null) {
      content.businessId = this.business.businessId; content.title = this.business.title; content.subtitle = this.business.subtitle; content.actionUrl = this.business.actionUrl
    }
    const message = new PteIMWireMessage()
    message.clientMsgId = this.clientMsgId
    message.serverMsgId = this.serverMsgId
    message.serverSeq = this.serverSeq
    message.conversationId = this.conversationId
    message.type = this.type
    message.createdAt = this.createdAt
    message.content = content
    return message
  }
}

export class PteIMConversation {
  conversationId: string
  lastMessage: PteIMMessage
  updatedAt: number
  constructor(conversationId: string, lastMessage: PteIMMessage, updatedAt: number) {
    this.conversationId = conversationId
    this.lastMessage = lastMessage
    this.updatedAt = updatedAt
  }
}

export class PteIMRemoteConversation {
  id: number
  type: string
  title: string
  avatar: string
  lastMessageSeq: number
  lastMessageSnapshot: string
  lastMessageAt: number
  unreadCount: number
  constructor(id: number, type: string, title: string, avatar: string,
    lastMessageSeq: number, lastMessageSnapshot: string, lastMessageAt: number, unreadCount: number) {
    this.id = id
    this.type = type
    this.title = title
    this.avatar = avatar
    this.lastMessageSeq = lastMessageSeq
    this.lastMessageSnapshot = lastMessageSnapshot
    this.lastMessageAt = lastMessageAt
    this.unreadCount = unreadCount
  }
}
export class PteIMConversationPage {
  total: number
  items: PteIMRemoteConversation[]
  constructor(total: number, items: PteIMRemoteConversation[]) { this.total = total; this.items = items }
}
export class PteIMRemoteMessage {
  messageId: number
  conversationId: number
  senderId: number
  clientMsgId: string
  type: string
  content: string
  payload: string
  seq: number
  sentAt: number
  recalledAt: number
  constructor(messageId: number, conversationId: number, senderId: number, clientMsgId: string,
    type: string, content: string, payload: string, seq: number, sentAt: number, recalledAt: number) {
    this.messageId = messageId
    this.conversationId = conversationId
    this.senderId = senderId
    this.clientMsgId = clientMsgId
    this.type = type
    this.content = content
    this.payload = payload
    this.seq = seq
    this.sentAt = sentAt
    this.recalledAt = recalledAt
  }
}
export class PteIMMessagePage {
  items: PteIMRemoteMessage[]
  constructor(items: PteIMRemoteMessage[]) { this.items = items }
}

/** Subclass this object or assign callbacks to receive SDK lifecycle events. */
export class PteIMListener {
  onConnectionChanged(_connected: boolean): void {}
  onMessage(_message: PteIMMessage): void {}
  onMessageStateChanged(_clientMsgId: string, _state: PteIMSendState): void {}
  onUserSigWillExpire(): void {}
  onUserSigExpired(): void {}
  onThemeModeChanged(_themeMode: PteIMThemeMode): void {}
  onLanguageChanged(_language: PteIMLanguage): void {}
  onError(_error: Error): void {}
}
