import { PteIMLanguage, PteIMListener, PteIMMessage, PteIMMessageType, PteIMSendState, PteIMThemeMode, PteLiveIM } from '@ptelive/im'
import { PteIMUIAction, PteIMUIActionHandler } from './PteIMUIKit'
import { PteIMUITheme } from './PteIMUITheme'

class PteIMUIChatListener extends PteIMListener {
  private changed: () => void
  constructor(changed: () => void) { super(); this.changed = changed }
  onMessage(_message: PteIMMessage): void { this.changed() }
  onMessageStateChanged(_clientMsgId: string, _state: PteIMSendState): void { this.changed() }
  onThemeModeChanged(_themeMode: PteIMThemeMode): void { this.changed() }
  onLanguageChanged(_language: PteIMLanguage): void { this.changed() }
}

/** Drop-in ArkUI conversation component for C2C and group conversations. */
@Component
export struct PteIMUIChat {
  @Prop client: PteLiveIM
  @Prop conversationId: string
  @Prop title: string = ''
  @Prop actionHandler: PteIMUIActionHandler = new PteIMUIActionHandler()
  @State messages: PteIMMessage[] = []
  @State draft: string = ''
  @State moreVisible: boolean = false
  @State dark: boolean = false
  private listener: PteIMUIChatListener | null = null

  aboutToAppear(): void {
    this.listener = new PteIMUIChatListener(() => { this.loadMessages(); this.applyAppearance() })
    this.client.addListener(this.listener)
    this.loadMessages(); this.applyAppearance()
  }
  aboutToDisappear(): void { if (this.listener !== null) this.client.removeListener(this.listener) }

  build() {
    Column() {
      Text(this.title.length > 0 ? this.title : this.conversationId).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.colorText()).width('100%').padding({ left: 18, right: 18, top: 16, bottom: 10 })
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.messages, (message: PteIMMessage) => {
            Row() {
              Text(this.messageText(message)).fontSize(15).fontColor(message.serverMsgId.length === 0 ? '#FFFFFF' : this.colorText()).backgroundColor(message.serverMsgId.length === 0 ? this.theme().outgoing : this.theme().incoming).borderRadius(16).padding(12)
            }.width('100%').justifyContent(message.serverMsgId.length === 0 ? FlexAlign.End : FlexAlign.Start)
          }, (message: PteIMMessage) => message.clientMsgId)
        }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }.layoutWeight(1)
      Row({ space: 8 }) {
        TextInput({ placeholder: 'Message', text: this.draft }).layoutWeight(1).onChange((value: string) => this.draft = value).onSubmit(() => this.sendText())
        Button('Send').onClick(() => this.sendText())
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
      Row({ space: 4 }) {
        Button('😀').onClick(() => this.client.sendEmoji(this.conversationId, 'default', 'smile_001'))
        Button('Image').onClick(() => this.actionHandler.request(PteIMUIAction.IMAGE))
        Button('Video').onClick(() => this.actionHandler.request(PteIMUIAction.VIDEO))
        Button('Voice').onClick(() => this.actionHandler.request(PteIMUIAction.VOICE))
        Button('More').onClick(() => this.moreVisible = !this.moreVisible)
      }.width('100%').padding({ left: 12, right: 12, bottom: 8 })
      if (this.moreVisible) {
        Row({ space: 4 }) {
          Button('Location').onClick(() => this.actionHandler.request(PteIMUIAction.LOCATION))
          Button('Gift').onClick(() => this.actionHandler.request(PteIMUIAction.GIFT))
          Button('Red packet').onClick(() => this.actionHandler.request(PteIMUIAction.RED_PACKET))
          Button('Order').onClick(() => this.actionHandler.request(PteIMUIAction.ORDER))
        }.width('100%').padding({ left: 12, right: 12, bottom: 12 })
      }
    }.width('100%').height('100%').backgroundColor(this.theme().background)
  }

  private async loadMessages(): Promise<void> { this.messages = await this.client.localMessages(this.conversationId, 0, 100) }
  private sendText(): void { const text = this.draft.trim(); if (text.length > 0) { this.client.sendText(this.conversationId, text); this.draft = ''; this.loadMessages() } }
  private applyAppearance(): void { this.dark = this.client.currentAppearance().themeMode === PteIMThemeMode.DARK }
  private theme(): PteIMUITheme { return PteIMUITheme.resolve(this.client) }
  private colorText(): string { return this.theme().text }
  private messageText(message: PteIMMessage): string {
    if (message.type === PteIMMessageType.TEXT) return message.text
    if (message.type === PteIMMessageType.EMOJI) return `${message.packageId}:${message.emojiId}`
    if (message.type === PteIMMessageType.LOCATION) return `[Location] ${message.location?.name ?? ''}`
    if (message.type === PteIMMessageType.GIFT) return `[Gift] ${message.business?.title ?? ''}`
    if (message.type === PteIMMessageType.RED_PACKET) return `[Red packet] ${message.business?.title ?? ''}`
    if (message.type === PteIMMessageType.ORDER) return `[Order] ${message.business?.title ?? ''}`
    return `[${message.type}]`
  }
}
