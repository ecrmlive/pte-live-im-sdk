import { PteIMLanguage, PteIMSDK, PteIMThemeMode } from '@ptelive/pte-im-sdk'
import { PteIMUITheme } from './PteIMUITheme'

/** Host-owned operations requested by the built-in chat controls. */
export enum PteIMUIAction { IMAGE = 'image', CAMERA = 'camera', VIDEO = 'video', VOICE = 'voice', LOCATION = 'location', GIFT = 'gift', RED_PACKET = 'red_packet', ORDER = 'order', FILE = 'file' }
export enum PteIMUIContactListMode { FRIENDS = 'friends', FOLLOWS = 'follows', GROUPS = 'groups', CUSTOM = 'custom' }

/** One 44 × 44 emoji cell. Custom emoji resources render at 24 × 32 inside the cell. */
export class PteIMUIEmojiItem {
  packageId: string
  emojiId: string
  text: string
  icon: Resource | null
  constructor(packageId: string, emojiId: string, text: string = emojiId, icon: Resource | null = null) {
    this.packageId = packageId; this.emojiId = emojiId; this.text = text; this.icon = icon
  }
}

/** Hosts may replace either common or all emoji sets without changing the input component. */
export class PteIMUIEmojiDataSource {
  common: PteIMUIEmojiItem[]
  all: PteIMUIEmojiItem[]
  constructor(common: PteIMUIEmojiItem[] = [], all: PteIMUIEmojiItem[] = []) { this.common = common; this.all = all }
}

/** Default eight actions plus up to four host-defined actions (three rows / twelve items maximum). */
export class PteIMUICustomAction {
  id: string
  titleZh: string
  titleEn: string
  icon: Resource
  constructor(id: string, titleZh: string, titleEn: string, icon: Resource) { this.id = id; this.titleZh = titleZh; this.titleEn = titleEn; this.icon = icon }
}

export function PteIMUIActionTitle(action: PteIMUIAction, language: PteIMLanguage): string {
  const english = language === PteIMLanguage.EN_US
  if (action === PteIMUIAction.IMAGE) return english ? 'Image' : '图片'
  if (action === PteIMUIAction.CAMERA) return english ? 'Camera' : '拍摄'
  if (action === PteIMUIAction.VIDEO) return english ? 'Video' : '视频'
  if (action === PteIMUIAction.LOCATION) return english ? 'Location' : '位置'
  if (action === PteIMUIAction.GIFT) return english ? 'Gift' : '礼物'
  if (action === PteIMUIAction.RED_PACKET) return english ? 'Red packet' : '红包'
  if (action === PteIMUIAction.ORDER) return english ? 'Order' : '订单'
  if (action === PteIMUIAction.FILE) return english ? 'File' : '文件'
  return english ? 'Voice' : '语音'
}

/** A host-owned action delegate. It keeps UIKit independent of media pickers and business pages. */
export class PteIMUIActionHandler {
  private callback: (action: PteIMUIAction) => void
  private businessCallback: (action: PteIMUIAction) => void
  private customCallback: (action: PteIMUICustomAction) => void

  constructor(callback: (action: PteIMUIAction) => void = (_action: PteIMUIAction) => {}, businessCallback: (action: PteIMUIAction) => void = callback, customCallback: (action: PteIMUICustomAction) => void = (_action: PteIMUICustomAction) => {}) {
    this.callback = callback; this.businessCallback = businessCallback; this.customCallback = customCallback
  }

  request(action: PteIMUIAction): void { this.callback(action) }
  requestBusiness(action: PteIMUIAction): void { this.businessCallback(action) }
  requestCustom(action: PteIMUICustomAction): void { this.customCallback(action) }
}

/** A host-owned selection delegate for the cache-first conversation list. */
export class PteIMUIConversationHandler {
  private callback: (conversationId: string, title: string) => void

  constructor(callback: (conversationId: string, title: string) => void = (_conversationId: string, _title: string) => {}) {
    this.callback = callback
  }

  select(conversationId: string, title: string = ''): void { this.callback(conversationId, title) }
}

/** Routes the chat back action to the host instead of assuming a navigation stack. */
export class PteIMUIChatNavigationHandler {
  private callback: () => void

  constructor(callback: () => void = () => {}) { this.callback = callback }

  back(): void { this.callback() }
}

/** Lets host apps persist appearance selections made from the conversation header. */
export class PteIMUIAppearanceHandler {
  private readonly themeCallback: (theme: PteIMThemeMode) => void
  private readonly languageCallback: (language: PteIMLanguage) => void

  constructor(themeCallback: (theme: PteIMThemeMode) => void = (_theme: PteIMThemeMode) => {}, languageCallback: (language: PteIMLanguage) => void = (_language: PteIMLanguage) => {}) {
    this.themeCallback = themeCallback
    this.languageCallback = languageCallback
  }

  selectTheme(theme: PteIMThemeMode): void { this.themeCallback(theme) }
  selectLanguage(language: PteIMLanguage): void { this.languageCallback(language) }
}

/** Receives a ready-to-open C2C or group conversation from the contact surface. */
export class PteIMUIContactHandler {
  private callback: (conversationId: string, title: string) => void
  constructor(callback: (conversationId: string, title: string) => void = (_conversationId: string, _title: string) => {}) { this.callback = callback }
  select(conversationId: string, title: string): void { this.callback(conversationId, title) }
}

/** Load errors stay with the host; UIKit never renders a transport-specific error page. */
export class PteIMUILoadErrorHandler {
  private callback: (message: string) => void
  constructor(callback: (message: string) => void = (_message: string) => {}) { this.callback = callback }
  receive(message: string): void { this.callback(message) }
}

/** Separate avatar hook so hosts can open a profile without entering a chat. */
export class PteIMUIAvatarHandler {
  private callback: (identifier: string, isGroup: boolean) => void
  constructor(callback: (identifier: string, isGroup: boolean) => void = (_identifier: string, _isGroup: boolean) => {}) { this.callback = callback }
  tap(identifier: string, isGroup: boolean): void { this.callback(identifier, isGroup) }
}

/** Lightweight factory namespace for the HarmonyOS PteIMUIKit package. */
export class PteIMUIKit {
  static chat(client: PteIMSDK, conversationId: string, title: string = '', theme: PteIMUITheme = new PteIMUITheme()): PteIMUIChatConfig {
    return new PteIMUIChatConfig(client, conversationId, title, theme)
  }
}

/** Pass this configuration to [PteIMUIChat] in an ArkUI page. */
export class PteIMUIChatConfig {
  client: PteIMSDK
  conversationId: string
  title: string
  theme: PteIMUITheme

  constructor(client: PteIMSDK, conversationId: string, title: string = '', theme: PteIMUITheme = new PteIMUITheme()) {
    this.client = client
    this.conversationId = conversationId
    this.title = title
    this.theme = theme
  }
}
