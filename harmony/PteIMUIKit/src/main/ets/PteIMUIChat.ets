import { PteIMLanguage, PteIMListener, PteIMMessage, PteIMMessageType, PteIMSendState, PteIMThemeMode, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUIAction, PteIMUIActionHandler } from './PteIMUIkit'
import { PteIMUITheme, PteIMUIThemePalette } from './PteIMUITheme'
import { PteIMUIInputBar, PteIMUIInputCallbacks } from './PteIMUIInputBar'

class PteIMUIChatListener extends PteIMListener {
  private changed: () => void
  constructor(changed: () => void) { super(); this.changed = changed }
  onMessage(_message: PteIMMessage): void { this.changed() }
  onMessageStateChanged(_clientMsgId: string, _state: PteIMSendState): void { this.changed() }
  onThemeModeChanged(_themeMode: PteIMThemeMode): void { this.changed() }
  onLanguageChanged(_language: PteIMLanguage): void { this.changed() }
}

export class PteIMUIVoiceRecordingHandler {
  private changed: (recording: boolean) => void
  constructor(changed: (recording: boolean) => void) { this.changed = changed }
  onChanged(recording: boolean): void { this.changed(recording) }
}

/** Drop-in ArkUI conversation component for C2C and group conversations. */
@Component
export struct PteIMUIChat {
  @Prop client: PteIMSDK
  @Prop conversationId: string
  @Prop title: string = ''
  @Prop actionHandler: PteIMUIActionHandler = new PteIMUIActionHandler()
  /** Host recorder lifecycle; use sendVoice after recording has been uploaded. */
  @Prop voiceRecordingHandler: PteIMUIVoiceRecordingHandler = new PteIMUIVoiceRecordingHandler((_recording: boolean) => {})
  @Prop theme: PteIMUITheme = new PteIMUITheme()
  @State messages: PteIMMessage[] = []
  @State draft: string = ''
  @StorageProp('colorMode') systemColorMode: string = 'light'
  private listener: PteIMUIChatListener | null = null

  aboutToAppear(): void {
    this.listener = new PteIMUIChatListener(() => this.loadMessages())
    this.client.addListener(this.listener)
    this.loadMessages()
  }
  aboutToDisappear(): void { if (this.listener !== null) this.client.removeListener(this.listener) }

  build() {
    Column() {
      Text(this.title.length > 0 ? this.title : this.conversationId).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().text).width('100%').padding({ left: 18, right: 18, top: 16, bottom: 10 })
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.messages, (message: PteIMMessage) => {
            Row() {
              Text(this.messageText(message)).fontSize(15).fontColor(this.isOutgoing(message) ? this.palette().outgoingText : this.palette().incomingText)
                .linearGradient(this.isOutgoing(message) ? { angle: 90, colors: [[this.palette().outgoingStart, 0.0], [this.palette().outgoingEnd, 1.0]] } : { angle: 90, colors: [[this.palette().incoming, 0.0], [this.palette().incoming, 1.0]] })
                .borderRadius(18).padding({ left: 14, right: 14, top: 10, bottom: 10 })
            }.width('100%').justifyContent(this.isOutgoing(message) ? FlexAlign.End : FlexAlign.Start)
          }, (message: PteIMMessage) => message.clientMsgId)
        }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }.layoutWeight(1)
      PteIMUIInputBar({ draft: $draft, palette: this.palette(), language: this.client.currentAppearance().language, callbacks: new PteIMUIInputCallbacks((text: string) => this.sendText(text), (packageId: string, emojiId: string) => { this.client.sendEmoji(this.conversationId, packageId, emojiId); this.loadMessages() }, (action: PteIMUIAction) => this.actionHandler.request(action), (recording: boolean) => this.voiceRecordingHandler.onChanged(recording)) })
    }.width('100%').height('100%').backgroundColor(this.palette().background)
  }

  private async loadMessages(): Promise<void> { this.messages = await this.client.localMessages(this.conversationId, 0, 100) }
  private sendText(text: string): void { const value = text.trim(); if (value.length > 0) { this.client.sendText(this.conversationId, value); this.loadMessages() } }
  private palette(): PteIMUIThemePalette { return PteIMUITheme.resolve(this.client, this.theme, this.systemColorMode === 'dark') }
  private isOutgoing(message: PteIMMessage): boolean { return message.senderId === this.client.currentUserId() }
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
