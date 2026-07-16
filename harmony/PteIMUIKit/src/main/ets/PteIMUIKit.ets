import { PteIMLanguage, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUITheme } from './PteIMUITheme'

/** Host-owned operations requested by the built-in chat controls. */
export enum PteIMUIAction { IMAGE = 'image', CAMERA = 'camera', VIDEO = 'video', VOICE = 'voice', LOCATION = 'location', GIFT = 'gift', RED_PACKET = 'red_packet', ORDER = 'order', FILE = 'file' }
export enum PteIMUIContactListMode { FRIENDS = 'friends', FOLLOWS = 'follows', GROUPS = 'groups', CUSTOM = 'custom' }

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

  constructor(callback: (action: PteIMUIAction) => void = (_action: PteIMUIAction) => {}) {
    this.callback = callback
  }

  request(action: PteIMUIAction): void { this.callback(action) }
}

/** A host-owned selection delegate for the cache-first conversation list. */
export class PteIMUIConversationHandler {
  private callback: (conversationId: string) => void

  constructor(callback: (conversationId: string) => void = (_conversationId: string) => {}) {
    this.callback = callback
  }

  select(conversationId: string): void { this.callback(conversationId) }
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
