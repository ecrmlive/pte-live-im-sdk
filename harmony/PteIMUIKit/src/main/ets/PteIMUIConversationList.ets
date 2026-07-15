import { PteIMConversation, PteIMListener, PteIMMessage, PteIMSendState, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUIConversationHandler } from './PteIMUIkit'

class PteIMUIConversationListener extends PteIMListener {
  private changed: () => void
  constructor(changed: () => void) { super(); this.changed = changed }
  onMessage(_message: PteIMMessage): void { this.changed() }
  onMessageStateChanged(_clientMsgId: string, _state: PteIMSendState): void { this.changed() }
}

/** Cache-first ArkUI conversation list. Server sync remains an explicit Core SDK operation. */
@Component
export struct PteIMUIConversationList {
  @Prop client: PteIMSDK
  @Prop conversationHandler: PteIMUIConversationHandler = new PteIMUIConversationHandler()
  @State conversations: PteIMConversation[] = []
  private listener: PteIMUIConversationListener | null = null
  aboutToAppear(): void { this.listener = new PteIMUIConversationListener(() => this.load()); this.client.addListener(this.listener); this.load() }
  aboutToDisappear(): void { if (this.listener !== null) this.client.removeListener(this.listener) }
  build() {
    List() {
      ForEach(this.conversations, (item: PteIMConversation) => {
        ListItem() { Column() { Text(item.conversationId).fontSize(16); Text(item.lastMessage.text.length > 0 ? item.lastMessage.text : `[${item.lastMessage.type}]`).fontSize(13).fontColor('#687385') }.padding(16).width('100%') }.onClick(() => this.conversationHandler.select(item.conversationId))
      }, (item: PteIMConversation) => item.conversationId)
    }.width('100%').height('100%')
  }
  private async load(): Promise<void> { this.conversations = await this.client.localConversations() }
}
