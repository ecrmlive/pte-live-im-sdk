/** Configuration that is shared by the application. Configure it before login. */
export enum PteIMThemeMode { SYSTEM = 'system', LIGHT = 'light', DARK = 'dark' }
export enum PteIMLanguage { SYSTEM = 'system', ZH_CN = 'zh-CN', EN_US = 'en-US' }
export enum PteIMMessageType {
  TEXT = 'text', EMOJI = 'emoji', IMAGE = 'image', VIDEO = 'video', VOICE = 'voice',
  LOCATION = 'location', GIFT = 'gift', RED_PACKET = 'red_packet', ORDER = 'order'
}
export enum PteIMSendState { PENDING = 'pending', UPLOADING = 'uploading', SENT = 'sent', FAILED = 'failed' }

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
  constructor(public themeMode: PteIMThemeMode, public language: PteIMLanguage) {}
}
export class PteIMMedia {
  constructor(public url: string = '', public thumbnailUrl: string = '', public coverUrl: string = '',
    public width: number = 0, public height: number = 0, public durationMs: number = 0, public sizeBytes: number = 0) {}
}
export class PteIMVoice {
  constructor(public url: string, public durationMs: number, public waveform: string = '', public sizeBytes: number = 0) {}
}
export class PteIMLocation {
  constructor(public latitude: number, public longitude: number, public name: string, public address: string = '') {}
}
export class PteIMBusinessContent {
  constructor(public businessId: string, public title: string, public subtitle: string = '', public actionUrl: string = '') {}
}

export class PteIMMessage {
  clientMsgId: string
  serverMsgId: string = ''
  serverSeq: number = 0
  createdAt: number
  state: PteIMSendState

  constructor(public conversationId: string, public type: PteIMMessageType, public text: string = '',
    public packageId: string = '', public emojiId: string = '', public media: PteIMMedia | null = null,
    public voice: PteIMVoice | null = null, public location: PteIMLocation | null = null,
    public business: PteIMBusinessContent | null = null, clientMsgId: string = '', createdAt: number = 0,
    state: PteIMSendState = PteIMSendState.PENDING) {
    this.clientMsgId = clientMsgId.length > 0 ? clientMsgId : PteIMMessage.newClientMsgId()
    this.createdAt = createdAt > 0 ? createdAt : Date.now()
    this.state = state
  }

  private static newClientMsgId(): string {
    return `${Date.now()}-${Math.floor(Math.random() * 1000000000)}`
  }

  toWire(): Record<string, Object> {
    const content: Record<string, Object> = {}
    if (this.text.length > 0) content['text'] = this.text
    if (this.packageId.length > 0) content['packageId'] = this.packageId
    if (this.emojiId.length > 0) content['emojiId'] = this.emojiId
    if (this.media !== null) {
      content['url'] = this.media.url; content['thumbnailUrl'] = this.media.thumbnailUrl; content['coverUrl'] = this.media.coverUrl
      content['width'] = this.media.width; content['height'] = this.media.height; content['durationMs'] = this.media.durationMs; content['sizeBytes'] = this.media.sizeBytes
    }
    if (this.voice !== null) {
      content['url'] = this.voice.url; content['durationMs'] = this.voice.durationMs; content['waveform'] = this.voice.waveform; content['sizeBytes'] = this.voice.sizeBytes
    }
    if (this.location !== null) {
      content['latitude'] = this.location.latitude; content['longitude'] = this.location.longitude; content['name'] = this.location.name; content['address'] = this.location.address
    }
    if (this.business !== null) {
      content['businessId'] = this.business.businessId; content['title'] = this.business.title; content['subtitle'] = this.business.subtitle; content['actionUrl'] = this.business.actionUrl
    }
    return { clientMsgId: this.clientMsgId, serverMsgId: this.serverMsgId, serverSeq: this.serverSeq,
      conversationId: this.conversationId, type: this.type, createdAt: this.createdAt, content: content }
  }
}

export class PteIMConversation {
  constructor(public conversationId: string, public lastMessage: PteIMMessage, public updatedAt: number) {}
}

export class PteIMRemoteConversation {
  constructor(public id: number, public type: string, public title: string, public avatar: string,
    public lastMessageSeq: number, public lastMessageSnapshot: string, public lastMessageAt: number, public unreadCount: number) {}
}
export class PteIMConversationPage { constructor(public total: number, public items: PteIMRemoteConversation[]) {} }
export class PteIMRemoteMessage {
  constructor(public messageId: number, public conversationId: number, public senderId: number, public clientMsgId: string,
    public type: string, public content: string, public payload: string, public seq: number, public sentAt: number, public recalledAt: number) {}
}
export class PteIMMessagePage { constructor(public items: PteIMRemoteMessage[]) {} }

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
