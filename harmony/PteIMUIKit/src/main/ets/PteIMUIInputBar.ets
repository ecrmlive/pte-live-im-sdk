import { PteIMLanguage } from '@ptelive/pte-im-sdk'
import { PteIMUIAction, PteIMUIActionTitle } from './PteIMUIKit'
import { PteIMUIThemePalette } from './PteIMUITheme'

/** Named callbacks keep this V1 ArkUI component free of unsupported Function props. */
export class PteIMUIInputCallbacks {
  private sendTextCallback: (text: string) => void
  private emojiSelectedCallback: (packageId: string, emojiId: string) => void
  private actionSelectedCallback: (action: PteIMUIAction) => void
  private voiceRecordingChangedCallback: (recording: boolean) => void

  constructor(sendTextCallback: (text: string) => void, emojiSelectedCallback: (packageId: string, emojiId: string) => void, actionSelectedCallback: (action: PteIMUIAction) => void, voiceRecordingChangedCallback: (recording: boolean) => void) {
    this.sendTextCallback = sendTextCallback
    this.emojiSelectedCallback = emojiSelectedCallback
    this.actionSelectedCallback = actionSelectedCallback
    this.voiceRecordingChangedCallback = voiceRecordingChangedCallback
  }

  sendText(text: string): void { this.sendTextCallback(text) }
  emojiSelected(packageId: string, emojiId: string): void { this.emojiSelectedCallback(packageId, emojiId) }
  actionSelected(action: PteIMUIAction): void { this.actionSelectedCallback(action) }
  voiceRecordingChanged(recording: boolean): void { this.voiceRecordingChangedCallback(recording) }
}

/** Reusable ArkUI InputBar; host owns actual media picker and audio recorder work. */
@Component
export struct PteIMUIInputBar {
  @Link draft: string
  @Prop palette: PteIMUIThemePalette
  @Prop language: PteIMLanguage = PteIMLanguage.ZH_CN
  @Prop callbacks: PteIMUIInputCallbacks
  @State voiceMode: boolean = false
  @State panel: string = ''

  build() {
    Column() {
      Row({ space: 6 }) {
        Button(this.voiceMode ? this.copy('keyboard') : this.copy('voice')).fontSize(12).fontColor(this.palette.icon).backgroundColor(Color.Transparent).onClick(() => { this.voiceMode = !this.voiceMode; this.panel = '' })
        if (this.voiceMode) {
          Button(this.copy('hold')).layoutWeight(1).height(38).fontSize(14).fontColor(this.palette.text).backgroundColor(this.palette.panelItem).borderRadius(16)
            .onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) this.callbacks.voiceRecordingChanged(true); if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.callbacks.voiceRecordingChanged(false) })
        } else {
          TextInput({ placeholder: this.copy('message'), text: this.draft }).layoutWeight(1).height(38).fontSize(15).fontColor(this.palette.text).placeholderColor(this.palette.muted).backgroundColor(Color.Transparent).onChange((value: string) => this.draft = value).onSubmit(() => this.submit())
        }
        Button('+').fontSize(23).fontColor(this.palette.icon).backgroundColor(Color.Transparent).onClick(() => this.panel = this.panel === 'more' ? '' : 'more')
        Button(this.copy('emoji')).fontSize(12).fontColor(this.palette.icon).backgroundColor(Color.Transparent).onClick(() => this.panel = this.panel === 'emoji' ? '' : 'emoji')
        Button(this.copy('send')).fontSize(13).fontColor(this.palette.outgoingText).linearGradient({ angle: 90, colors: [[this.palette.outgoingStart, 0.0], [this.palette.outgoingEnd, 1.0]] }).borderRadius(18).onClick(() => this.submit())
      }.width('100%').height(52).padding({ left: 10, right: 10 }).backgroundColor(this.palette.surface).border({ width: 1, color: this.palette.divider, radius: 24 })
      if (this.panel === 'emoji') { this.emojiPanel() }
      if (this.panel === 'more') { this.morePanel() }
    }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.palette.composer)
  }

  @Builder emojiPanel() {
    Row({ space: 6 }) {
      ForEach(['smile_001', 'smile_002', 'wave_001', 'heart_001', 'thumb_001', 'party_001'], (emojiId: string) => {
        Button(this.emojiText(emojiId)).layoutWeight(1).height(56).fontSize(22).fontColor(this.palette.icon).backgroundColor(this.palette.panelItem).borderRadius(14).onClick(() => { this.callbacks.emojiSelected('default', emojiId); this.panel = '' })
      }, (emojiId: string) => emojiId)
    }.width('100%').height(104).padding(12).backgroundColor(this.palette.panel)
  }

  @Builder morePanel() {
    Row({ space: 6 }) {
      ForEach([PteIMUIAction.IMAGE, PteIMUIAction.CAMERA, PteIMUIAction.VIDEO, PteIMUIAction.LOCATION, PteIMUIAction.FILE, PteIMUIAction.GIFT, PteIMUIAction.RED_PACKET, PteIMUIAction.ORDER], (action: PteIMUIAction) => {
        Button(PteIMUIActionTitle(action, this.language)).layoutWeight(1).height(56).fontSize(11).fontColor(this.palette.icon).backgroundColor(this.palette.panelItem).borderRadius(14).onClick(() => { this.callbacks.actionSelected(action); this.panel = '' })
      }, (action: PteIMUIAction) => action.toString())
    }.width('100%').height(104).padding(12).backgroundColor(this.palette.panel)
  }

  private submit(): void { const value = this.draft.trim(); if (value.length > 0) { this.callbacks.sendText(value); this.draft = ''; this.panel = '' } }
  private emojiText(id: string): string { if (id === 'smile_001') return '☺'; if (id === 'smile_002') return '✦'; if (id === 'wave_001') return '◌'; if (id === 'heart_001') return '♥'; if (id === 'thumb_001') return '✓'; return '✺' }
  private copy(key: string): string { const english = this.language === PteIMLanguage.EN_US; if (key === 'message') return english ? 'Message' : '输入消息'; if (key === 'send') return english ? 'Send' : '发送'; if (key === 'hold') return english ? 'Hold to talk' : '按住说话'; if (key === 'voice') return english ? 'Voice' : '语音'; if (key === 'keyboard') return english ? 'Keyboard' : '键盘'; return english ? 'Emoji' : '表情' }
}
