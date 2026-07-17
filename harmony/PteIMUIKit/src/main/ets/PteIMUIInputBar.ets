import { PteIMLanguage } from '@ptelive/pte-im-sdk'
import { PteIMUIAction, PteIMUIActionTitle, PteIMUICustomAction, PteIMUIEmojiDataSource, PteIMUIEmojiItem } from './PteIMUIKit'
import { PteIMUIThemePalette } from './PteIMUITheme'

/** Named callbacks keep this V1 ArkUI component free of unsupported Function props. */
export class PteIMUIInputCallbacks {
  private sendTextCallback: (text: string) => void
  private emojiSelectedCallback: (packageId: string, emojiId: string, text: string) => void
  private actionSelectedCallback: (action: PteIMUIAction) => void
  private customActionSelectedCallback: (action: PteIMUICustomAction) => void
  private voiceRecordingChangedCallback: (recording: boolean) => void

  constructor(sendTextCallback: (text: string) => void, emojiSelectedCallback: (packageId: string, emojiId: string, text: string) => void, actionSelectedCallback: (action: PteIMUIAction) => void, voiceRecordingChangedCallback: (recording: boolean) => void, customActionSelectedCallback: (action: PteIMUICustomAction) => void = (_action: PteIMUICustomAction) => {}) {
    this.sendTextCallback = sendTextCallback
    this.emojiSelectedCallback = emojiSelectedCallback
    this.actionSelectedCallback = actionSelectedCallback; this.customActionSelectedCallback = customActionSelectedCallback
    this.voiceRecordingChangedCallback = voiceRecordingChangedCallback
  }

  sendText(text: string): void { this.sendTextCallback(text) }
  emojiSelected(packageId: string, emojiId: string, text: string): void { this.emojiSelectedCallback(packageId, emojiId, text) }
  actionSelected(action: PteIMUIAction): void { this.actionSelectedCallback(action) }
  customActionSelected(action: PteIMUICustomAction): void { this.customActionSelectedCallback(action) }
  voiceRecordingChanged(recording: boolean): void { this.voiceRecordingChangedCallback(recording) }
}

/** Reusable ArkUI InputBar with voice, emoji, and a three-row action panel. */
@Component
export struct PteIMUIInputBar {
  @Link draft: string
  @Prop palette: PteIMUIThemePalette
  @Prop language: PteIMLanguage = PteIMLanguage.ZH_CN
  @Prop callbacks: PteIMUIInputCallbacks
  @Prop emojiDataSource: PteIMUIEmojiDataSource = new PteIMUIEmojiDataSource()
  @Prop customActions: PteIMUICustomAction[] = []
  /** Incremented by the chat content when the user taps or starts a vertical drag. */
  @Link @Watch('onDismissSignalChanged') dismissSignal: number
  /** Incremented by a message reaction menu when its plus button opens the emoji keyboard. */
  @Link @Watch('onEmojiOpenSignalChanged') emojiOpenSignal: number
  @State voiceMode: boolean = false
  @State recording: boolean = false
  @State cancelRecording: boolean = false
  // The visual picker opens on the complete smiley grid. The clock tab toggles recent items.
  @State emojiTab: string = 'all'
  @State emojiHistory: PteIMUIEmojiItem[] = []
  @State panel: string = ''
  @State keyboardActive: boolean = false

  build() {
    Column() {
      Row({ space: 6 }) {
        Button() {
          if (this.voiceMode) Image(this.isDark() ? $r('app.media.PteIMUIChatTextModeDark') : $r('app.media.PteIMUIChatTextModeLight')).width(40).height(40).objectFit(ImageFit.Contain)
          else Image(this.isDark() ? $r('app.media.PteIMUIChatVoiceModeDark') : $r('app.media.PteIMUIChatVoiceModeLight')).width(40).height(40).objectFit(ImageFit.Contain)
        }.width(40).height(40).padding(0).backgroundColor(Color.Transparent).onClick(() => { this.dismissTransientUi(); this.voiceMode = !this.voiceMode; this.recording = false })
        if (this.voiceMode) {
          Button() {
            Row({ space: 7 }) {
              if (this.recording) Image($r('app.media.PteIMUIChatVoiceModeDark')).width(21).height(21).objectFit(ImageFit.Contain)
              Text(this.recording ? (this.cancelRecording ? this.copy('cancel') : this.copy('talking')) : this.copy('hold')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.recording ? Color.White : this.palette.text)
            }.justifyContent(FlexAlign.Center)
          }.layoutWeight(1).height(40).backgroundColor(this.recording ? this.palette.outgoingEnd : this.palette.composerInput).borderRadius(12)
            .onTouch((event: TouchEvent) => this.handleVoiceTouch(event))
          Button() { this.moreToggleIcon() }.width(40).height(40).padding(0).backgroundColor(Color.Transparent).onClick(() => this.toggleMorePanel())
        } else {
          TextArea({ placeholder: this.copy('message'), text: this.draft }).layoutWeight(1).height(this.inputHeight()).minLines(1).maxLines(5).maxLength(200).fontSize(15).fontColor(this.palette.text).placeholderColor(this.palette.muted).backgroundColor(this.palette.composerInput).borderRadius(12).padding({ left: 10, right: 10, top: 8, bottom: 8 }).enterKeyType(EnterKeyType.Send).onFocus(() => { this.keyboardActive = true; this.panel = '' }).onBlur(() => this.keyboardActive = false).onChange((value: string) => this.draft = value.substring(0, 200)).onSubmit(() => this.submit())
          Button() { this.emojiToggleIcon() }.width(40).height(40).padding(0).backgroundColor(Color.Transparent).onClick(() => this.toggleEmojiPanel())
          Button() { this.moreToggleIcon() }.width(40).height(40).padding(0).backgroundColor(Color.Transparent).onClick(() => this.toggleMorePanel())
        }
      }.width('100%').height(this.voiceMode ? 56 : this.inputHeight() + 16).alignItems(VerticalAlign.Center).padding({ left: 12, right: 12 }).backgroundColor(this.palette.surface).border({ width: { top: 1 }, color: this.palette.divider })
      if (this.panel === 'emoji') { this.emojiPanel() }
      if (this.panel === 'more') { this.morePanel() }
    }.width('100%').backgroundColor(this.palette.composer)
  }

  @Builder emojiPanel() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: 6 }) {
        this.emojiCategoryBar()
        Text(this.isEnglish() ? 'SMILEYS' : '表情').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.palette.muted).width('100%').padding({ left: 18, right: 18 })
        if (this.emojiTab === 'common') {
          // Keep the compact history row attached to the heading, never vertically centred.
          this.emojiRows()
          Blank().layoutWeight(1)
        } else {
          Scroll() {
            this.emojiRows()
          }.layoutWeight(1).scrollBar(BarState.Auto)
        }
      // The controls float over the lower-right corner instead of consuming a
      // whole row. The grid keeps its full visible height and can scroll past
      // the controls for the final items.
      }.width('100%').height('100%').padding({ top: 6 })
      Row({ space: 10 }) {
        Button() {
          Image(this.isDark() ? $r('app.media.PteIMUIChatEmojiBackspaceDark') : $r('app.media.PteIMUIChatEmojiBackspaceLight')).width(44).height(44).objectFit(ImageFit.Contain)
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).onClick(() => this.removeLastEmoji())
        Button() {
          Image(this.isDark() ? $r('app.media.PteIMUIChatEmojiSendDark') : $r('app.media.PteIMUIChatEmojiSendLight')).width(44).height(44).objectFit(ImageFit.Contain)
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).onClick(() => this.submit())
      }.width('100%').height(48).justifyContent(FlexAlign.End).padding({ right: 14, bottom: 4 })
    }.width('100%').height(338).backgroundColor(this.palette.panel).border({ width: { top: 1 }, color: this.palette.divider })
  }

  @Builder emojiCategoryBar() {
    Row({ space: 8 }) {
      this.emojiHistoryButton()
      this.emojiCategoryButton('all', '😀', this.emojiTab === 'all')
      this.emojiCategoryButton('all', '👋')
      this.emojiCategoryButton('all', '❤')
      this.emojiCategoryButton('all', '🐶')
      this.emojiCategoryButton('all', '🍎')
      this.emojiCategoryButton('all', '⚽')
      this.emojiCategoryButton('all', '🚗')
      this.emojiCategoryButton('all', '💡')
      this.emojiCategoryButton('all', '🎉')
    }.width('100%').height(44).justifyContent(FlexAlign.SpaceAround).padding({ left: 8, right: 8 }).border({ width: { bottom: 1 }, color: this.palette.divider })
  }

  @Builder emojiCategoryButton(key: string, icon: string, selected: boolean = false) {
    Button() {
      if (icon === 'history') Image($r('app.media.PteIMUIChatEmojiHistory')).width(36).height(32).objectFit(ImageFit.Contain)
      else {
        Row() {
          Text(icon).fontSize(22)
        }.width(40).height(40).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      }
    }.width(40).height(40).padding(0).backgroundColor(Color.Transparent).borderRadius(20).onClick(() => this.emojiTab = key)
  }

  /** The history button is a toggle: recent-used items first, the full default grid on a second tap. */
  @Builder emojiHistoryButton() {
    Button() {
      Image($r('app.media.PteIMUIChatEmojiHistory')).width(36).height(32).objectFit(ImageFit.Contain)
    }.width(40).height(40).padding(0).backgroundColor(Color.Transparent).borderRadius(20)
      .onClick(() => this.emojiTab = this.emojiTab === 'common' ? 'all' : 'common')
  }

  @Builder emojiRows() {
    Column({ space: 8 }) {
      ForEach(this.emojiGridRows(), (row: PteIMUIEmojiItem[], index: number) => {
        this.emojiRow(row)
      }, (_row: PteIMUIEmojiItem[], index: number) => `emoji-row-${index}`)
    // The two 44px floating controls sit above this grid. Keep scroll-only
    // tail space so the final emoji row can rise above their hit areas.
    }.width('100%').padding({ left: 12, right: 12, bottom: 58 })
  }

  @Builder emojiRow(values: PteIMUIEmojiItem[]) {
    Row() {
      ForEach(values, (emoji: PteIMUIEmojiItem) => {
        Button() {
          if (emoji.icon !== null) Image(emoji.icon).width(24).height(32).objectFit(ImageFit.Contain)
          else Text(emoji.text).fontSize(28)
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).onClick(() => {
          this.rememberEmoji(emoji)
          this.callbacks.emojiSelected(emoji.packageId, emoji.emojiId, emoji.text)
        })
      }, (emoji: PteIMUIEmojiItem) => `${emoji.packageId}-${emoji.emojiId}`)
    }.width('100%').justifyContent(FlexAlign.SpaceAround).height(44)
  }

  @Builder morePanel() {
    Column({ space: 20 }) {
      this.actionRow([PteIMUIAction.IMAGE, PteIMUIAction.CAMERA, PteIMUIAction.VIDEO, PteIMUIAction.LOCATION])
      this.actionRow([PteIMUIAction.FILE, PteIMUIAction.RED_PACKET, PteIMUIAction.GIFT, PteIMUIAction.ORDER])
      if (this.customActions.length > 0) this.customActionRow(this.customActions.slice(0, 4))
    }.width('100%').height(this.customActions.length > 0 ? 285 : 190).padding({ left: 20, right: 20, top: 10, bottom: 10 }).backgroundColor(this.palette.panel)
  }

  @Builder actionRow(actions: PteIMUIAction[]) {
    Row({ space: 20 }) { ForEach(actions, (action: PteIMUIAction) => { this.actionTile(action) }, (action: PteIMUIAction) => action.toString()) }.width('100%').height(75)
  }

  @Builder actionTile(action: PteIMUIAction) {
    Column({ space: 8 }) {
      Button() {
        if (action === PteIMUIAction.IMAGE) Image($r('app.media.PteIMUIChatActionImage')).width(52).height(52)
        else if (action === PteIMUIAction.VIDEO) Image($r('app.media.PteIMUIChatActionVideo')).width(52).height(52)
        else if (action === PteIMUIAction.LOCATION) Image($r('app.media.PteIMUIChatActionLocation')).width(52).height(52)
        else if (action === PteIMUIAction.CAMERA) Image($r('app.media.PteIMUIChatActionCamera')).width(52).height(52)
        else if (action === PteIMUIAction.FILE) Image($r('app.media.PteIMUIChatActionFile')).width(52).height(52)
        else if (action === PteIMUIAction.RED_PACKET) Image($r('app.media.PteIMUIChatActionRedPacket')).width(52).height(52)
        else if (action === PteIMUIAction.GIFT) Image($r('app.media.PteIMUIChatActionGift')).width(52).height(52)
        else if (action === PteIMUIAction.ORDER) Image($r('app.media.PteIMUIChatActionOrder')).width(52).height(52)
      }.width(52).height(52).padding(0).backgroundColor(Color.Transparent).onClick(() => { this.callbacks.actionSelected(action); this.panel = '' })
      Text(PteIMUIActionTitle(action, this.language)).height(15).lineHeight(15).fontSize(12).fontColor(this.palette.muted).maxLines(1)
    }.layoutWeight(1).height(75).alignItems(HorizontalAlign.Center)
  }

  @Builder customActionRow(actions: PteIMUICustomAction[]) {
    Row({ space: 20 }) { ForEach(actions, (action: PteIMUICustomAction) => { this.customActionTile(action) }, (action: PteIMUICustomAction) => action.id) }.width('100%').height(75)
  }

  @Builder customActionTile(action: PteIMUICustomAction) {
    Column({ space: 8 }) { Button() { Image(action.icon).width(52).height(52).objectFit(ImageFit.Contain) }.width(52).height(52).padding(0).backgroundColor(Color.Transparent).onClick(() => { this.callbacks.customActionSelected(action); this.panel = '' }); Text(this.isEnglish() ? action.titleEn : action.titleZh).height(15).lineHeight(15).fontSize(12).fontColor(this.palette.muted).maxLines(1) }.layoutWeight(1).height(75).alignItems(HorizontalAlign.Center)
  }

  private submit(): void { const value = this.draft.trim(); if (value.length > 0) { this.callbacks.sendText(value); this.draft = ''; this.panel = '' } }
  private inputHeight(): number {
    const hardLines = this.draft.split('\n').length
    const wrappedLines = Math.ceil(this.draft.length / 26)
    return Math.max(40, Math.min(100, Math.max(hardLines, wrappedLines) * 21 + 16))
  }
  private isDark(): boolean { return this.palette.background === '#0E111C' }
  private isEnglish(): boolean { return this.language === PteIMLanguage.EN_US }
  private currentEmojis(): PteIMUIEmojiItem[] {
    const fallback = ['😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '☺', '😃', '😉', '😊', '😇', '😍', '😘', '😋', '😗', '😙', '😚', '😛', '😜', '😝', '😏', '😐', '😑', '😶', '🙄', '😬', '🤔', '😥', '😪', '😴', '😭', '😠', '😡', '😎', '🤓', '😷', '🤒', '🤕', '😵', '🤠', '🤡', '🤥', '🤤', '😱', '😨', '😰']
    const all = this.emojiDataSource.all.length > 0 ? this.emojiDataSource.all : fallback.map((value: string) => new PteIMUIEmojiItem('system', value, value))
    if (this.emojiTab !== 'common') return all
    // Until an emoji has been used, the host's common set provides a useful initial history state.
    if (this.emojiHistory.length > 0) return this.emojiHistory
    return this.emojiDataSource.common.length > 0 ? this.emojiDataSource.common : all.slice(0, 8)
  }
  private emojiGridRows(): PteIMUIEmojiItem[][] {
    const rows: PteIMUIEmojiItem[][] = []
    const values = this.currentEmojis()
    for (let index = 0; index < values.length; index += 8) rows.push(values.slice(index, index + 8))
    return rows
  }
  private toggleEmojiPanel(): void { this.dismissKeyboard(); this.panel = this.panel === 'emoji' ? '' : 'emoji' }
  private toggleMorePanel(): void { this.dismissKeyboard(); this.panel = this.panel === 'more' ? '' : 'more' }
  private dismissKeyboard(): void { this.keyboardActive = false; this.getUIContext().getFocusController().clearFocus() }
  private dismissTransientUi(): void { this.panel = ''; this.dismissKeyboard() }
  onDismissSignalChanged(): void { this.dismissTransientUi() }
  onEmojiOpenSignalChanged(): void { this.voiceMode = false; this.dismissKeyboard(); this.panel = 'emoji' }
  /**
   * ArkTS' Array.from currently iterates UTF-16 code units on this target.
   * Drop a complete trailing surrogate pair so an emoji never leaves a visible
   * replacement-character glyph in the editor.
   */
  private removeLastEmoji(): void {
    const length = this.draft.length
    if (length === 0) return
    const trailingUnit = this.draft.charCodeAt(length - 1)
    const isLowSurrogate = trailingUnit >= 0xDC00 && trailingUnit <= 0xDFFF
    this.draft = this.draft.substring(0, Math.max(0, length - (isLowSurrogate ? 2 : 1)))
  }
  private rememberEmoji(emoji: PteIMUIEmojiItem): void {
    const identifier = `${emoji.packageId}-${emoji.emojiId}`
    this.emojiHistory = [emoji, ...this.emojiHistory.filter((item: PteIMUIEmojiItem) => `${item.packageId}-${item.emojiId}` !== identifier)].slice(0, 24)
  }
  @Builder private emojiToggleIcon() { Image(this.panel === 'emoji' ? (this.isDark() ? $r('app.media.PteIMUIChatEmojiActiveDark') : $r('app.media.PteIMUIChatEmojiActiveLight')) : (this.isDark() ? $r('app.media.PteIMUIChatEmojiDefaultDark') : $r('app.media.PteIMUIChatEmojiDefaultLight'))).width(40).height(40).objectFit(ImageFit.Contain) }
  @Builder private moreToggleIcon() { Image(this.panel === 'more' ? (this.isDark() ? $r('app.media.PteIMUIChatMoreActiveDark') : $r('app.media.PteIMUIChatMoreActiveLight')) : (this.isDark() ? $r('app.media.PteIMUIChatMoreDefaultDark') : $r('app.media.PteIMUIChatMoreDefaultLight'))).width(40).height(40).objectFit(ImageFit.Contain) }
  private handleVoiceTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) { this.recording = true; this.cancelRecording = false; this.callbacks.voiceRecordingChanged(true) }
    if (event.type === TouchType.Move && this.recording && event.touches.length > 0) { const point = event.touches[0]; this.cancelRecording = point.x < -8 || point.y < -8 || point.y > 48 }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.recording = false; this.cancelRecording = false; this.callbacks.voiceRecordingChanged(false) }
  }
  private copy(key: string): string { const english = this.language === PteIMLanguage.EN_US; if (key === 'message') return english ? 'Say something...' : '说点什么...'; if (key === 'send') return english ? 'Send' : '发送'; if (key === 'hold') return english ? 'Hold to Record' : '按住录音'; if (key === 'talking') return english ? 'Talking' : '正在说话'; if (key === 'cancel') return english ? 'Release to cancel' : '松开手取消录音'; return english ? 'Emoji' : '表情' }
}
