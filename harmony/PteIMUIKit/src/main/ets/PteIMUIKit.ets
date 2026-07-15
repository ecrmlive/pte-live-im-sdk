import { PteIMLanguage, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUITheme } from './PteIMUITheme'

/** Host-owned operations requested by the built-in chat controls. */
export enum PteIMUIAction { IMAGE = 'image', VIDEO = 'video', VOICE = 'voice', LOCATION = 'location', GIFT = 'gift', RED_PACKET = 'red_packet', ORDER = 'order' }

export function PteIMUIActionTitle(action: PteIMUIAction, language: PteIMLanguage): string {
  const english = language === PteIMLanguage.EN_US
  if (action === PteIMUIAction.IMAGE) return english ? 'Image' : '图片'
  if (action === PteIMUIAction.VIDEO) return english ? 'Video' : '视频'
  if (action === PteIMUIAction.LOCATION) return english ? 'Location' : '位置'
  if (action === PteIMUIAction.GIFT) return english ? 'Gift' : '礼物'
  if (action === PteIMUIAction.RED_PACKET) return english ? 'Red packet' : '红包'
  if (action === PteIMUIAction.ORDER) return english ? 'Order' : '订单'
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

/** Lightweight factory namespace for the HarmonyOS PteIMUIkit package. */
export class PteIMUIkit {
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
