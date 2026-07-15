import { PteLiveIM } from '@ptelive/im'

/** Host-owned operations requested by the built-in chat controls. */
export enum PteIMUIAction { IMAGE = 'image', VIDEO = 'video', VOICE = 'voice', LOCATION = 'location', GIFT = 'gift', RED_PACKET = 'red_packet', ORDER = 'order' }

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

/** Lightweight factory namespace for the HarmonyOS PteIMUIKit package. */
export class PteIMUIKit {
  static chat(client: PteLiveIM, conversationId: string, title: string = ''): PteIMUIChatConfig {
    return new PteIMUIChatConfig(client, conversationId, title)
  }
}

/** Pass this configuration to [PteIMUIChat] in an ArkUI page. */
export class PteIMUIChatConfig {
  client: PteLiveIM
  conversationId: string
  title: string

  constructor(client: PteLiveIM, conversationId: string, title: string = '') {
    this.client = client
    this.conversationId = conversationId
    this.title = title
  }
}
