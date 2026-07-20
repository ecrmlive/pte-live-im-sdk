import { PteIMBusinessContent, PteIMLanguage, PteIMListener, PteIMLocation, PteIMMedia, PteIMMessage, PteIMMessageType, PteIMSendState, PteIMThemeMode, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUIAction, PteIMUIActionHandler, PteIMUIChatNavigationHandler, PteIMUILocationPickerHandler, PteIMUIMediaPreviewHandler, PteIMUIMediaPreviewNavigationHandler, PteIMUIMessageOperationHandler, PteIMUIReadReceiptProvider } from './PteIMUIKit'
import { PteIMUITheme, PteIMUIThemePalette } from './PteIMUITheme'
import { PteIMUIInputBar, PteIMUIInputCallbacks } from './PteIMUIInputBar'
import { PteIMUICustomAction, PteIMUIEmojiDataSource } from './PteIMUIKit'
import { PteIMUIFilePreview, PteIMUIImagePreview, PteIMUIVideoPreview } from './PteIMUIMediaPreview'
import { PteIMUIMediaPlayback } from './PteIMUIMediaPlayback'
import { PteIMUIAvatar } from './PteIMUIAvatar'
import photoAccessHelper from '@ohos.file.photoAccessHelper'
import picker from '@ohos.file.picker'
import cameraPicker from '@ohos.multimedia.cameraPicker'
import camera from '@ohos.multimedia.camera'
import geoLocationManager from '@ohos.geoLocationManager'
import pasteboard from '@ohos.pasteboard'
import { bundleManager, common } from '@kit.AbilityKit'
import { KeyboardAvoidMode } from '@ohos.arkui.UIContext'

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
  private cancelled: () => void
  constructor(changed: (recording: boolean) => void, cancelled: () => void = () => {}) { this.changed = changed; this.cancelled = cancelled }
  onChanged(recording: boolean): void { this.changed(recording) }
  onCancelled(): void { this.cancelled() }
}

/** Host-owned reaction data. UIKit only renders it and never persists it in Core. */
export class PteIMUIReaction {
  emoji: string
  count: number
  constructor(emoji: string, count: number) { this.emoji = emoji; this.count = count < 0 ? 0 : count }
}

export class PteIMUIReactionProvider {
  reactionsFor(_message: PteIMMessage): PteIMUIReaction[] { return [] }
  /** Return the persisted current-user vote so UIKit can toggle it without guessing. */
  reactedByMe(_message: PteIMMessage, _emoji: string): boolean { return false }
}

/** UI-local reaction delta. Hosts can still provide their persisted counts through reactionProvider. */
export class PteIMUILocalReaction {
  messageId: string
  emoji: string
  addedByMe: boolean
  constructor(messageId: string, emoji: string, addedByMe: boolean) {
    this.messageId = messageId; this.emoji = emoji; this.addedByMe = addedByMe
  }
}

class PteIMUIMapTarget {
  id: string
  uri: string
  constructor(id: string, uri: string) { this.id = id; this.uri = uri }
}

/**
 * MessageKit-style display model. A host transformer can change every visible
 * message field without replacing the SDK message, delivery state or storage.
 */
export class PteIMUIMessagePresentation {
  text: string
  time: string
  avatar: string
  senderName: string
  constructor(text: string, time: string, avatar: string, senderName: string) {
    this.text = text; this.time = time; this.avatar = avatar; this.senderName = senderName
  }
}

/** Subclass and override transform() to rewrite chat cell text, metadata or avatar. */
export class PteIMUIMessagePresentationTransformer {
  transform(_message: PteIMMessage, _outgoing: boolean, value: PteIMUIMessagePresentation): PteIMUIMessagePresentation { return value }
}

/** Drop-in ArkUI chat surface with independently reusable MessageKit-like cells and input bar. */
@Component
export struct PteIMUIChat {
  @Prop client: PteIMSDK | null = null
  @Prop conversationId: string
  @Prop title: string = ''
  /** Negative keeps the default circle; set vp to customise header and message avatars. */
  @Prop avatarCornerRadius: number = -1
  /** Explicit conversation type supplied by the host; the title fallback keeps older integrations compatible. */
  @Prop groupConversation: boolean = false
  @Prop actionHandler: PteIMUIActionHandler = new PteIMUIActionHandler()
  @Prop navigationHandler: PteIMUIChatNavigationHandler = new PteIMUIChatNavigationHandler()
  @Prop voiceRecordingHandler: PteIMUIVoiceRecordingHandler = new PteIMUIVoiceRecordingHandler((_recording: boolean) => {})
  @Prop navigationSubtitleText: string = ''
  @Prop reactionProvider: PteIMUIReactionProvider = new PteIMUIReactionProvider()
  @Prop operationHandler: PteIMUIMessageOperationHandler = new PteIMUIMessageOperationHandler()
  @Prop readReceiptProvider: PteIMUIReadReceiptProvider = new PteIMUIReadReceiptProvider()
  @Prop locationPickerHandler: PteIMUILocationPickerHandler = new PteIMUILocationPickerHandler()
  @Prop mediaPreviewHandler: PteIMUIMediaPreviewHandler = new PteIMUIMediaPreviewHandler()
  @Prop presentationTransformer: PteIMUIMessagePresentationTransformer = new PteIMUIMessagePresentationTransformer()
  @Prop theme: PteIMUITheme = new PteIMUITheme()
  /** A host may inject local preview messages before a live IM session is available. */
  @Prop previewMessages: PteIMMessage[] = []
  @Prop previewUserId: string = 'preview-user'
  @Prop previewDark: boolean = false
  @Prop previewLanguage: PteIMLanguage = PteIMLanguage.ZH_CN
  @Prop emojiDataSource: PteIMUIEmojiDataSource = new PteIMUIEmojiDataSource()
  @Prop customActions: PteIMUICustomAction[] = []
  @State messages: PteIMMessage[] = []
  @State draft: string = ''
  @State selectedMessageId: string = ''
  @State quotedMessageId: string = ''
  @State quotedText: string = ''
  @State composerDismissSignal: number = 0
  @State emojiOpenSignal: number = 0
  @State localReactions: PteIMUILocalReaction[] = []
  @State previewVisible: boolean = false
  @State previewType: PteIMMessageType = PteIMMessageType.IMAGE
  @State previewMediaUri: string = ''
  @State filePreviewVisible: boolean = false
  @State previewFileName: string = ''
  @State mapPickerVisible: boolean = false
  @State mapLatitude: number = 0
  @State mapLongitude: number = 0
  @State mapName: string = ''
  @State mapStatus: string = ''
  @State availableMapTargetIds: string[] = []
  @StorageProp('colorMode') systemColorMode: string = 'light'
  private listener: PteIMUIChatListener | null = null

  aboutToAppear(): void {
    // Keep the secondary navigation bar pinned while the IME changes the usable height.
    // OFFSET moves the entire page (including navigation) upward; RESIZE only compresses the message area.
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    if (this.client === null) {
      this.messages = this.previewMessages
      return
    }
    this.listener = new PteIMUIChatListener(() => this.loadMessages())
    this.client.addListener(this.listener)
    this.loadMessages()
  }

  aboutToDisappear(): void { if (this.listener !== null && this.client !== null) this.client.removeListener(this.listener) }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.navigationBar()
        Scroll() {
          Column({ space: 10 }) {
            this.dayDivider()
            ForEach(this.messages, (message: PteIMMessage) => this.messageRow(message), (message: PteIMMessage) => message.clientMsgId)
          }.width('100%').padding({ left: 12, right: 12, top: 14, bottom: 14 })
        }.layoutWeight(1).scrollBar(BarState.Off).backgroundColor(this.palette().background)
          .onTouch((event: TouchEvent) => this.dismissComposerForContentInteraction(event))
        PteIMUIInputBar({
          draft: $draft,
          palette: this.palette(),
          language: this.currentLanguage(),
          callbacks: new PteIMUIInputCallbacks(
            (text: string) => { this.sendText(text) },
            (_packageId: string, _emojiId: string, text: string) => { this.draft = (this.draft + text).substring(0, 200) },
            (action: PteIMUIAction) => this.handleInputAction(action),
            (recording: boolean) => this.voiceRecordingHandler.onChanged(recording),
            (action: PteIMUICustomAction) => this.actionHandler.requestCustom(action),
            () => this.voiceRecordingHandler.onCancelled(),
          ),
          emojiDataSource: this.emojiDataSource,
          customActions: this.customActions,
          dismissSignal: $composerDismissSignal,
          emojiOpenSignal: $emojiOpenSignal,
        })
      }.width('100%').height('100%').backgroundColor(this.palette().background)
      if (this.previewVisible && this.previewType === PteIMMessageType.IMAGE) PteIMUIImagePreview({ uri: this.previewMediaUri, handler: this.mediaPreviewHandler, navigationHandler: new PteIMUIMediaPreviewNavigationHandler(() => this.closeMediaPreview()) })
      if (this.previewVisible && this.previewType === PteIMMessageType.VIDEO) PteIMUIVideoPreview({ uri: this.previewMediaUri, handler: this.mediaPreviewHandler, navigationHandler: new PteIMUIMediaPreviewNavigationHandler(() => this.closeMediaPreview()) })
      if (this.filePreviewVisible) PteIMUIFilePreview({ uri: this.previewMediaUri, fileName: this.previewFileName, handler: this.mediaPreviewHandler, navigationHandler: new PteIMUIMediaPreviewNavigationHandler(() => this.closeFilePreview()) })
      if (this.mapPickerVisible) this.mapPickerOverlay()
    }.width('100%').height('100%').backgroundColor(this.palette().background)
  }

  /** Touching the transcript or beginning a vertical scroll always restores the clean chat canvas. */
  private dismissComposerForContentInteraction(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.selectedMessageId = ''
      this.composerDismissSignal += 1
    }
  }

  /** Only map apps that can resolve their navigation link are displayed. */
  @Builder private mapPickerOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Text('').width('100%').height('100%').backgroundColor('#66000000').onClick(() => this.mapPickerVisible = false)
      Column({ space: 4 }) {
        Text(this.isEnglish() ? 'Navigate to destination' : '选择导航地图').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().text).margin({ bottom: 8 })
        Text(this.mapName).fontSize(12).fontColor(this.palette().muted).maxLines(1).margin({ bottom: 6 })
        if (this.availableMapTargetIds.length === 0) {
          Text(this.isEnglish() ? 'No supported map app is installed' : '未检测到可用地图应用').width('100%').fontSize(13).fontColor(this.palette().muted).textAlign(TextAlign.Center).margin({ top: 18, bottom: 18 })
        } else {
          if (this.availableMapTargetIds.indexOf('amap') >= 0) this.mapTargetButton(this.isEnglish() ? 'Amap' : '高德地图', 'amap')
          if (this.availableMapTargetIds.indexOf('baidu') >= 0) this.mapTargetButton(this.isEnglish() ? 'Baidu Maps' : '百度地图', 'baidu')
          if (this.availableMapTargetIds.indexOf('tencent') >= 0) this.mapTargetButton(this.isEnglish() ? 'Tencent Maps' : '腾讯地图', 'tencent')
          if (this.availableMapTargetIds.indexOf('google') >= 0) this.mapTargetButton(this.isEnglish() ? 'Google Maps' : '谷歌地图', 'google')
          if (this.availableMapTargetIds.indexOf('system') >= 0) this.mapTargetButton(this.isEnglish() ? 'System Maps' : '系统地图', 'system')
        }
        if (this.mapStatus.length > 0) Text(this.mapStatus).fontSize(11).fontColor('#F0444F').margin({ top: 7 })
        Button(this.isEnglish() ? 'Cancel' : '取消').width('100%').height(42).fontSize(14).fontColor(this.palette().muted).backgroundColor(Color.Transparent).margin({ top: 5 }).onClick(() => this.mapPickerVisible = false)
      }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 20 }).backgroundColor(this.palette().surface).borderRadius({ topLeft: 22, topRight: 22 })
    }.width('100%').height('100%')
  }

  @Builder private mapTargetButton(title: string, target: string) {
    Button(title).width('100%').height(44).fontSize(14).fontColor(this.palette().text).backgroundColor(this.palette().incoming).borderRadius(12).onClick(() => this.openExternalMap(target))
  }

  @Builder private navigationBar() {
    Row() {
      Button() {
        Image(this.isDark() ? $r('app.media.PteIMUIChatNavBackDark') : $r('app.media.PteIMUIChatNavBackLight')).width(44).height(44).objectFit(ImageFit.Fill)
      }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).onClick(() => this.navigationHandler.back())
      PteIMUIAvatar({ label: this.isGroup() ? '#' : this.avatarForTitle(), avatarSize: 34, cornerRadius: this.avatarCornerRadius, fillColor: this.palette().outgoingEnd }).margin({ left: 4, right: 9 })
      Column({ space: 2 }) {
        Text(this.title.length > 0 ? this.title : this.conversationId).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.palette().text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.navigationSubtitleText.length > 0 ? this.navigationSubtitleText : (this.isGroup() ? (this.isEnglish() ? '8 members' : '8位成员') : (this.isEnglish() ? 'Online' : '在线'))).fontSize(10).fontColor('#17B979')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button() { Image(this.isDark() ? $r('app.media.PteIMUIChatNavMoreDark') : $r('app.media.PteIMUIChatNavMoreNativeLight')).width(44).height(44).objectFit(ImageFit.Fill) }
        .width(44).height(44).padding(0).backgroundColor(Color.Transparent).onClick(() => this.navigationHandler.more())
    }.width('100%').height(44).flexShrink(0).padding({ left: 10, right: 9 }).backgroundColor(this.palette().surface).border({ width: { bottom: 1 }, color: this.palette().divider })
  }

  @Builder private dayDivider() {
    Row({ space: 10 }) {
      Blank().layoutWeight(1).height(1).backgroundColor(this.palette().divider)
      Text(this.isEnglish() ? 'Today' : '今天').fontSize(10).fontColor(this.palette().muted)
      Blank().layoutWeight(1).height(1).backgroundColor(this.palette().divider)
    }.width('100%').padding({ left: 12, right: 12, top: 3, bottom: 7 })
  }

  @Builder private messageRow(message: PteIMMessage) {
    Row({ space: 8 }) {
      if (!this.isOutgoing(message)) this.avatar(this.presentation(message, false).avatar)
      Column({ space: 3 }) {
        if (this.isGroup() && !this.isOutgoing(message)) Text(this.presentation(message, false).senderName).fontSize(10).fontColor(this.palette().muted).margin({ left: 4 })
        if (this.selectedMessageId === message.clientMsgId) this.messageActionBar(message)
        this.messageContent(message, this.presentation(message, this.isOutgoing(message)), this.isOutgoing(message))
        this.reactionSummary(message)
        this.messageMeta(message, this.presentation(message, this.isOutgoing(message)), this.isOutgoing(message))
      }.alignItems(this.isOutgoing(message) ? HorizontalAlign.End : HorizontalAlign.Start)
      if (this.isOutgoing(message)) this.avatar(this.presentation(message, true).avatar)
    }.width('100%').justifyContent(this.isOutgoing(message) ? FlexAlign.End : FlexAlign.Start).alignItems(VerticalAlign.Top)
  }

  @Builder private avatar(label: string) { PteIMUIAvatar({ label: label, avatarSize: 26, cornerRadius: this.avatarCornerRadius, fillColor: '#8650F2' }) }

  @Builder private messageContent(message: PteIMMessage, presentation: PteIMUIMessagePresentation, outgoing: boolean) {
    if (message.type === PteIMMessageType.VOICE) this.voiceBubble(message, outgoing)
    else if (this.isRich(message)) this.richMessageCard(message, presentation, outgoing)
    else {
      Column({ space: message.quoteText.length > 0 ? 5 : 0 }) {
        if (message.quoteText.length > 0) Text(`↪ ${message.quoteText}`).fontSize(10).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(outgoing ? '#E9DEFF' : this.palette().muted).padding({ bottom: 4 }).border({ width: { bottom: 1 }, color: outgoing ? '#33FFFFFF' : this.palette().divider })
        Text(presentation.text).fontSize(14).lineHeight(20).fontColor(outgoing ? this.palette().outgoingText : this.palette().incomingText)
      }.padding({ left: 13, right: 13, top: 9, bottom: 9 }).borderRadius(15).constraintSize({ maxWidth: '75%' })
        .backgroundColor(outgoing ? this.palette().outgoingEnd : this.palette().incoming).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    }
  }

  @Builder private voiceBubble(message: PteIMMessage, outgoing: boolean) {
    Row({ space: 5 }) {
      if (outgoing) Text(`${this.voiceSeconds(message)}s`).width(34).fontSize(12).fontColor(Color.White).textAlign(TextAlign.Center)
      Image(outgoing
        ? (this.isDark() ? $r('app.media.PteIMUIChatVoiceOutgoingDark') : $r('app.media.PteIMUIChatVoiceOutgoingLight'))
        : (this.isDark() ? $r('app.media.PteIMUIChatVoiceIncomingDark') : $r('app.media.PteIMUIChatVoiceIncomingLight')))
        .width(22).height(22).objectFit(ImageFit.Contain)
      if (!outgoing) Text(`${this.voiceSeconds(message)}s`).width(34).fontSize(12).fontColor(this.palette().muted).textAlign(TextAlign.Center)
    }.width(88).height(42).padding({ left: 10, right: 10 }).alignItems(VerticalAlign.Center)
      .backgroundColor(outgoing ? this.palette().outgoingEnd : this.palette().incoming).borderRadius(16)
      .onClick(() => PteIMUIMediaPlayback.playVoice(`voice:${message.clientMsgId}`, message.voice?.url ?? ''))
      .gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
  }

  @Builder private richMessageCard(message: PteIMMessage, presentation: PteIMUIMessagePresentation, outgoing: boolean) {
    if (message.type === PteIMMessageType.LOCATION) {
      Column({ space: 0 }) {
        Image($r('app.media.PteIMUIChatLocationMap'))
          .width(210)
          .height(92)
          .objectFit(ImageFit.Cover)
          .borderRadius({ topLeft: 16, topRight: 16 })
        Column({ space: 3 }) { Text(message.location?.name ?? presentation.text).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette().text); Text(message.location?.address ?? '').fontSize(9).fontColor(this.palette().muted).maxLines(1) }.width(210).padding(10).backgroundColor(this.palette().surface).borderRadius({ bottomLeft: 16, bottomRight: 16 })
      }.borderRadius(16).clip(true).onClick(() => this.showMapPicker(message.location)).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    } else if (message.type === PteIMMessageType.IMAGE) {
      Stack({ alignContent: Alignment.Center }) {
        // Figma stops: A684FF/60%, AD46FF/40%, 00D3F3/50%; the Fill opacity is 10%.
        Text('').width(164).height(136).linearGradient({ direction: GradientDirection.Right, colors: this.isDark() ? [['#0FA684FF', 0.0], ['#0AAD46FF', 0.5], ['#0D00D3F3', 1.0]] : [['#801D293D', 0.0], ['#800F172B', 0.5], ['#80000000', 1.0]] })
        Column({ space: 5 }) { Image($r('app.media.PteIMUIChatPhotoIcon')).width(29).height(29).objectFit(ImageFit.Contain); Text(this.isEnglish() ? 'Photo' : '照片').fontSize(11).fontColor(Color.White) }.alignItems(HorizontalAlign.Center)
      }.borderRadius(16).clip(true).onClick(() => this.openMediaPreview(message)).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    } else if (message.type === PteIMMessageType.VIDEO) {
      Stack({ alignContent: Alignment.Center }) {
        Text('').width(188).height(122).linearGradient({ direction: GradientDirection.Right, colors: this.isDark() ? [['#0FA684FF', 0.0], ['#0AAD46FF', 0.5], ['#0D00D3F3', 1.0]] : [['#801D293D', 0.0], ['#800F172B', 0.5], ['#80000000', 1.0]] })
        Text('').width(46).height(46).backgroundColor('#1AFFFFFF').border({ width: 1, color: '#33FFFFFF' }).borderRadius(23)
        Image($r('app.media.PteIMUIChatVideoPlay')).width(20).height(20).objectFit(ImageFit.Contain)
        Stack({ alignContent: Alignment.BottomEnd }) {
          Text('').width(188).height(122)
          Row({ space: 4 }) {
            Image($r('app.media.PteIMUIChatVideoDuration')).width(12).height(12).objectFit(ImageFit.Contain)
            Text(this.videoDuration(message)).width(38).fontSize(10).lineHeight(24).fontColor('#CCFFFFFF').maxLines(1)
          }.width(72).height(24).padding({ left: 6, right: 6 }).alignItems(VerticalAlign.Center).backgroundColor('#1AFFFFFF').borderRadius(12).margin({ right: 8, bottom: 8 })
        }.width(188).height(122)
      }.width(188).height(122).borderRadius(16).clip(true).onClick(() => this.openMediaPreview(message)).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    } else if (message.type === PteIMMessageType.RED_PACKET || message.type === PteIMMessageType.GIFT) {
      Stack({ alignContent: Alignment.Center }) {
        Image(message.type === PteIMMessageType.RED_PACKET ? $r('app.media.PteIMUIChatRedPacketCard') : $r('app.media.PteIMUIChatGiftCard')).width(196).height(188).objectFit(ImageFit.Fill)
        Column({ space: 4 }) {
          // Only the card copy moves down: the claimed/received footer keeps its artwork baseline.
          Blank().height(82)
          Column({ space: 4 }) {
            Text(message.business?.title ?? presentation.text).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFE972')
            Text(message.business?.subtitle ?? '').fontSize(10).fontColor(Color.White)
          }.alignItems(HorizontalAlign.Center).translate({ y: 7 })
          Blank().layoutWeight(1)
          Stack({ alignContent: Alignment.Center }) {
            Text(this.richCardStatus(message)).width('100%').textAlign(TextAlign.Center).fontSize(11).fontWeight(FontWeight.Medium).fontColor('#FFE972')
          }.width('100%').height(38).border({ width: { top: 1 }, color: message.type === PteIMMessageType.RED_PACKET ? '#804E230E' : '#80A4004E' })
        }.width(196).height(188).alignItems(HorizontalAlign.Center)
      }.borderRadius(16).clip(true).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    } else if (message.type === PteIMMessageType.ORDER) {
      Column({ space: 7 }) {
        Row({ space: 9 }) { Stack({ alignContent: Alignment.Center }) { Text('').width(54).height(54).backgroundColor(this.isDark() ? '#28344A' : '#E7EDF5').borderRadius(12); Image($r('app.media.PteIMUIChatOrderIcon')).width(30).height(30).objectFit(ImageFit.Contain) }.width(54).height(54); Column({ space: 2 }) { Text(message.business?.title ?? presentation.text).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette().text).maxLines(2); Text(message.business?.subtitle ?? '').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#EE3B46') }.layoutWeight(1).alignItems(HorizontalAlign.Start) }.width('100%')
        Row() { Text(this.isEnglish() ? 'Order' : '订单').fontSize(10).fontColor(this.palette().muted); Blank().layoutWeight(1); Text(this.isEnglish() ? 'View Order ›' : '查看订单 ›').fontSize(10).fontColor(this.palette().outgoingEnd) }.width('100%').border({ width: { top: 1 }, color: this.palette().divider }).padding({ top: 7 })
      }.width(190).padding(11).linearGradient({ direction: GradientDirection.Right, colors: this.isDark() ? [['#0FA684FF', 0.0], ['#0AAD46FF', 0.5], ['#0D00D3F3', 1.0]] : [['#FFFFFFFF', 0.0], ['#FFFFFFFF', 0.5], ['#FFFFFFFF', 1.0]] }).borderRadius(15).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    } else if (message.type === PteIMMessageType.FILE) {
      Row({ space: 10 }) {
        Image($r('app.media.PteIMUIChatActionFile')).width(36).height(36).objectFit(ImageFit.Contain)
        Column({ space: 4 }) {
          Text(message.media?.fileName ?? presentation.text).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.fileTitleColor(outgoing)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.fileSize(message.media?.sizeBytes ?? 0)).fontSize(10).fontColor(this.fileSizeColor(outgoing))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width(210).padding(11).backgroundColor(outgoing ? this.palette().outgoingEnd : this.palette().surface).borderRadius(15).onClick(() => this.openFilePreview(message)).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    } else {
      Text(presentation.text).fontSize(14).fontColor(this.palette().text).width(188).padding(12).backgroundColor(this.palette().surface).borderRadius(15).gesture(LongPressGesture().onAction(() => this.selectMessage(message.clientMsgId)))
    }
  }

  @Builder private messageMeta(message: PteIMMessage, presentation: PteIMUIMessagePresentation, outgoing: boolean) {
    Row({ space: 4 }) {
      Text(presentation.time).fontSize(9).fontColor(this.palette().muted)
      if (outgoing && message.state === PteIMSendState.FAILED) Button('!').width(16).height(16).fontSize(11).fontColor(Color.White).backgroundColor('#F0444F').borderRadius(8).padding(0).onClick(() => this.retryMessage(message))
      else if (outgoing) Image(this.deliveryIcon(message)).width(12).height(12)
    }.padding({ left: 3, right: 3 })
  }

  @Builder private messageActionBar(message: PteIMMessage) {
    Column({ space: 7 }) {
      Row({ space: 12 }) {
        this.reactionButton(message, '👍')
        this.reactionButton(message, '❤️')
        this.reactionButton(message, '😂')
        this.reactionButton(message, '😮')
        this.reactionButton(message, '😭')
        this.reactionButton(message, '🙏')
        Blank().width(1).height(22).backgroundColor(this.palette().divider)
        Button() { Text('+').fontSize(24).fontColor(this.palette().muted).width(24).textAlign(TextAlign.Center) }
          .width(28).height(32).padding(0).backgroundColor(Color.Transparent).onClick(() => this.openReactionEmoji())
      }.height(44).padding({ left: 12, right: 12 }).backgroundColor(this.palette().surface).borderRadius(14).shadow({ radius: 10, color: this.isDark() ? '#33000000' : '#22000000', offsetY: 4 })
      Row({ space: 0 }) {
        this.contextButton(this.isEnglish() ? 'Quote' : '引用', this.isDark() ? $r('app.media.PteIMUIChatQuoteDark') : $r('app.media.PteIMUIChatQuoteLight'), false, () => this.quoteMessage(message))
        if (message.type === PteIMMessageType.TEXT) this.contextButton(this.isEnglish() ? 'Copy' : '复制', this.isDark() ? $r('app.media.PteIMUIChatCopyDark') : $r('app.media.PteIMUIChatCopyLight'), false, () => this.copyMessage(message))
        if (this.isOutgoing(message)) {
          this.contextButton(this.isEnglish() ? 'Revoke' : '撤回', this.isDark() ? $r('app.media.PteIMUIChatRevokeDark') : $r('app.media.PteIMUIChatRevokeLight'), false, () => this.revokeMessage(message))
          this.contextButton(this.isEnglish() ? 'Delete' : '删除', this.isDark() ? $r('app.media.PteIMUIChatDeleteDark') : $r('app.media.PteIMUIChatDeleteLight'), true, () => this.deleteMessage(message))
        }
      }.width(this.contextMenuWidth(message)).height(42).backgroundColor(this.palette().surface).borderRadius(14).shadow({ radius: 10, color: this.isDark() ? '#33000000' : '#22000000', offsetY: 4 })
    }.alignItems(this.isOutgoing(message) ? HorizontalAlign.End : HorizontalAlign.Start)
      // Prevent the transcript's outside-tap handler from closing this card before a menu action is delivered.
      .onTouch((event: TouchEvent) => event.stopPropagation())
  }

  @Builder private reactionButton(message: PteIMMessage, value: string) {
    Button() { Text(value).fontSize(20).width(23).height(28).textAlign(TextAlign.Center) }
      .width(23).height(28).padding(0).backgroundColor(Color.Transparent).onClick(() => this.toggleReaction(message, value))
  }

  @Builder private reactionSummary(message: PteIMMessage) {
    if (this.reactionValues(message).length > 0) {
      Row({ space: 5 }) {
        ForEach(this.reactionValues(message), (reaction: PteIMUIReaction) => {
          Button() {
            Text(`${reaction.emoji}${reaction.count > 1 ? ` ${reaction.count}` : ''}`).fontSize(12).fontColor(this.palette().text)
          }.height(25).padding({ left: 8, right: 8, top: 0, bottom: 0 }).backgroundColor(this.palette().surface).border({ width: 1, color: this.palette().divider }).borderRadius(13)
            .onClick(() => this.toggleReaction(message, reaction.emoji))
        }, (reaction: PteIMUIReaction) => `${message.clientMsgId}-${reaction.emoji}`)
      }.padding({ top: 2, bottom: 1 }).width('100%').justifyContent(this.isOutgoing(message) ? FlexAlign.End : FlexAlign.Start)
    }
  }

  @Builder private contextButton(title: string, icon: Resource, destructive: boolean, action: () => void) {
    Button() {
      Row({ space: 4 }) {
        Image(icon).width(15).height(15)
        Text(title).fontSize(10).fontColor(destructive ? '#F0444F' : this.palette().text)
      }.justifyContent(FlexAlign.Center)
    }.layoutWeight(1).height(42).backgroundColor(Color.Transparent).padding(0).border({ width: { right: destructive ? 0 : 1 }, color: this.palette().divider }).onClick(action)
  }

  private async loadMessages(): Promise<void> { if (this.client !== null) this.messages = await this.client.localMessages(this.conversationId, 0, 100) }
  private contextMenuWidth(message: PteIMMessage): number {
    let count = 1
    if (message.type === PteIMMessageType.TEXT) count += 1
    if (this.isOutgoing(message)) count += 2
    return count * 90
  }
  private async copyMessage(message: PteIMMessage): Promise<void> {
    try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.messageText(message))) } catch (_error) {}
    this.selectedMessageId = ''
  }
  private async sendText(text: string): Promise<void> {
    const value = text.trim(); if (value.length === 0) return
    if (this.client === null) {
      const message = new PteIMMessage(this.conversationId, PteIMMessageType.TEXT, value, '', '', null, null, null, null, '', Date.now(), PteIMSendState.SENT)
      message.senderId = this.previewUserId
      message.quoteClientMsgId = this.quotedMessageId
      message.quoteText = this.quotedText
      this.messages = [...this.messages, message]
    } else {
      if (this.quotedMessageId.length > 0) await this.client.sendTextWithQuote(this.conversationId, value, this.quotedMessageId, this.quotedText)
      else await this.client.sendText(this.conversationId, value)
      await this.loadMessages()
    }
    this.quotedMessageId = ''
    this.quotedText = ''
  }
  private async sendEmoji(packageId: string, emojiId: string): Promise<void> {
    if (this.client === null) {
      const message = new PteIMMessage(this.conversationId, PteIMMessageType.EMOJI, '', packageId, emojiId, null, null, null, null, '', Date.now(), PteIMSendState.SENT)
      message.senderId = this.previewUserId
      this.messages = [...this.messages, message]
    } else { await this.client.sendEmoji(this.conversationId, packageId, emojiId); await this.loadMessages() }
  }
  private async handleInputAction(action: PteIMUIAction): Promise<void> {
    if (action === PteIMUIAction.RED_PACKET || action === PteIMUIAction.GIFT || action === PteIMUIAction.ORDER) { this.actionHandler.requestBusiness(action); return }
    if (action === PteIMUIAction.IMAGE) { const uri = await this.pickPhoto(false); if (uri.length > 0) await this.sendPickedMedia(PteIMMessageType.IMAGE, new PteIMMedia(uri, uri, '', 720, 960, 0, 0, this.fileName(uri), 'image/*')); return }
    if (action === PteIMUIAction.VIDEO) { const uri = await this.pickPhoto(true); if (uri.length > 0) await this.sendPickedMedia(PteIMMessageType.VIDEO, new PteIMMedia(uri, '', uri, 1280, 720, 0, 0, this.fileName(uri), 'video/*')); return }
    if (action === PteIMUIAction.CAMERA) { const uri = await this.capturePhoto(); if (uri.length > 0) await this.sendPickedMedia(PteIMMessageType.IMAGE, new PteIMMedia(uri, uri, '', 720, 960, 0, 0, this.fileName(uri), 'image/*')); return }
    if (action === PteIMUIAction.FILE) { const uri = await this.pickFile(); if (uri.length > 0) await this.sendPickedMedia(PteIMMessageType.FILE, new PteIMMedia(uri, '', '', 0, 0, 0, 0, this.fileName(uri), 'application/octet-stream')); return }
    if (action === PteIMUIAction.LOCATION) { await this.sendCurrentLocation(); return }
    this.actionHandler.request(action)
  }
  private async sendPickedMedia(type: PteIMMessageType, media: PteIMMedia): Promise<void> {
    if (this.client !== null) {
      const localPath = this.localPath(media.url)
      if (type === PteIMMessageType.IMAGE) await this.client.uploadAndSendImage(this.conversationId, localPath, media.mimeType)
      else if (type === PteIMMessageType.VIDEO) await this.client.uploadAndSendVideo(this.conversationId, localPath, media.mimeType)
      else await this.client.uploadAndSendFile(this.conversationId, localPath, media.mimeType)
      await this.loadMessages()
      return
    }
    const message = new PteIMMessage(this.conversationId, type, '', '', '', media, null, null, null, '', Date.now(), PteIMSendState.SENT); message.senderId = this.previewUserId; this.messages = [...this.messages, message]
  }
  private async pickPhoto(video: boolean): Promise<string> {
    try { const option = new photoAccessHelper.PhotoSelectOptions(); option.MIMEType = video ? photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE : photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE; option.maxSelectNumber = 1; const result = await new photoAccessHelper.PhotoViewPicker().select(option); return result.photoUris.length > 0 ? result.photoUris[0] : '' } catch (_error) { return '' }
  }
  private async capturePhoto(): Promise<string> {
    try { const profile: cameraPicker.PickerProfile = { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK }; const result = await cameraPicker.pick(getContext(this), [cameraPicker.PickerMediaType.PHOTO], profile); return result.resultUri } catch (_error) { return '' }
  }
  private async pickFile(): Promise<string> {
    try { const option = new picker.DocumentSelectOptions(); option.maxSelectNumber = 1; const values = await new picker.DocumentViewPicker().select(option); return values.length > 0 ? values[0] : '' } catch (_error) { return '' }
  }
  private async sendCurrentLocation(): Promise<void> {
    let location = await this.locationPickerHandler.pick()
    if (location === null) {
      try {
        const current = await geoLocationManager.getCurrentLocation()
        location = new PteIMLocation(current.latitude, current.longitude, this.isEnglish() ? 'Current location' : '当前位置', `${current.latitude.toFixed(5)}, ${current.longitude.toFixed(5)}`)
      } catch (_error) { this.actionHandler.request(PteIMUIAction.LOCATION); return }
    }
    if (this.client !== null) { await this.client.sendLocation(this.conversationId, location); await this.loadMessages() }
    else { const message = new PteIMMessage(this.conversationId, PteIMMessageType.LOCATION, '', '', '', null, null, location, null, '', Date.now(), PteIMSendState.SENT); message.senderId = this.previewUserId; this.messages = [...this.messages, message] }
  }

  private openMediaPreview(message: PteIMMessage): void {
    this.selectedMessageId = ''
    this.previewType = message.type
    this.previewMediaUri = message.type === PteIMMessageType.VIDEO
      ? (message.media?.url ?? '')
      : (message.media?.thumbnailUrl || message.media?.url || '')
    this.previewVisible = true
  }

  private closeMediaPreview(): void {
    this.previewVisible = false
    this.previewMediaUri = ''
  }

  private openFilePreview(message: PteIMMessage): void {
    this.selectedMessageId = ''
    this.previewMediaUri = message.media?.url ?? ''
    this.previewFileName = message.media?.fileName ?? this.fileName(this.previewMediaUri)
    this.filePreviewVisible = true
  }

  private closeFilePreview(): void {
    this.filePreviewVisible = false
    this.previewFileName = ''
    this.previewMediaUri = ''
  }

  private showMapPicker(location: PteIMLocation | null): void {
    if (location === null) return
    this.selectedMessageId = ''
    this.mapLatitude = location.latitude
    this.mapLongitude = location.longitude
    this.mapName = location.name
    this.mapStatus = ''
    this.detectAvailableMapTargets()
    this.mapPickerVisible = true
  }

  private mapTargets(): PteIMUIMapTarget[] {
    const encodedName = encodeURIComponent(this.mapName)
    const latitude = this.mapLatitude.toFixed(6)
    const longitude = this.mapLongitude.toFixed(6)
    return [
      new PteIMUIMapTarget('amap', `amapuri://route/plan/?dlat=${latitude}&dlon=${longitude}&dname=${encodedName}&dev=0&t=0`),
      new PteIMUIMapTarget('baidu', `baidumap://map/direction?destination=latlng:${latitude},${longitude}|name=${encodedName}&mode=driving`),
      new PteIMUIMapTarget('tencent', `qqmap://map/routeplan?type=drive&tocoord=${latitude},${longitude}&to=${encodedName}`),
      new PteIMUIMapTarget('google', `google.navigation:q=${latitude},${longitude}`),
      new PteIMUIMapTarget('system', `geo:${latitude},${longitude}?q=${latitude},${longitude}(${encodedName})`),
    ]
  }

  /** Query before rendering the sheet so unavailable map names are never tappable. */
  private detectAvailableMapTargets(): void {
    const available: string[] = []
    for (const target of this.mapTargets()) {
      try {
        if (bundleManager.canOpenLink(target.uri)) available.push(target.id)
      } catch (_error) {}
    }
    this.availableMapTargetIds = available
  }

  private async openExternalMap(preferred: string): Promise<void> {
    const target = this.mapTargets().find((item: PteIMUIMapTarget) => item.id === preferred)
    if (target === undefined) return
    const context = getContext(this) as common.UIAbilityContext
    try {
      await context.startAbility({ action: 'ohos.want.action.viewData', uri: target.uri })
      this.mapPickerVisible = false
    } catch (_error) {
      this.availableMapTargetIds = this.availableMapTargetIds.filter((id: string) => id !== preferred)
      this.mapStatus = this.isEnglish() ? 'This map app is unavailable' : '该地图应用暂不可用'
    }
  }
  private localPath(uri: string): string { return uri.startsWith('file://') ? uri.substring(7) : uri }
  private fileName(uri: string): string {
    const normalized = uri.split('?')[0]
    const index = normalized.lastIndexOf('/')
    return index >= 0 ? normalized.substring(index + 1) : normalized
  }
  /* Preview-only fallback remains for unsupported local picker environments. */
  private appendPreviewBusiness(action: PteIMUIAction): void {
    let type: PteIMMessageType = PteIMMessageType.TEXT
    let media: PteIMMedia | null = null
    let location: PteIMLocation | null = null
    let business: PteIMBusinessContent | null = null
    if (action === PteIMUIAction.IMAGE || action === PteIMUIAction.CAMERA) { type = PteIMMessageType.IMAGE; media = new PteIMMedia('', '', '', 720, 960, 0, 0, 'Photo') }
    else if (action === PteIMUIAction.VIDEO) { type = PteIMMessageType.VIDEO; media = new PteIMMedia('', '', '', 1280, 720, 24000, 0, 'video.mp4') }
    else if (action === PteIMUIAction.LOCATION) { type = PteIMMessageType.LOCATION; location = new PteIMLocation(31.2304, 121.4737, this.isEnglish() ? 'Zhangjiang Hi-Tech Park' : '张江高科技园区', 'Pudong, Shanghai') }
    else if (action === PteIMUIAction.FILE) { type = PteIMMessageType.FILE; media = new PteIMMedia('', '', '', 0, 0, 0, 1024 * 300, this.isEnglish() ? 'Proposal.pdf' : '项目报价单.pdf', 'application/pdf') }
    else if (action === PteIMUIAction.RED_PACKET) { type = PteIMMessageType.RED_PACKET; business = new PteIMBusinessContent(`preview-red-${Date.now()}`, this.isEnglish() ? 'Me' : '我', this.isEnglish() ? 'Best wishes!' : '恭喜发财，大吉大利') }
    else if (action === PteIMUIAction.GIFT) { type = PteIMMessageType.GIFT; business = new PteIMBusinessContent(`preview-gift-${Date.now()}`, this.isEnglish() ? 'Starlight Box' : '星光礼盒', this.isEnglish() ? 'Open your gift' : '打开礼物') }
    else if (action === PteIMUIAction.ORDER) { type = PteIMMessageType.ORDER; business = new PteIMBusinessContent(`preview-order-${Date.now()}`, 'iPhone 15 Pro 256GB', '¥8,999') }
    const message = new PteIMMessage(this.conversationId, type, '', '', '', media, null, location, business, '', Date.now(), PteIMSendState.SENT)
    message.senderId = this.previewUserId
    this.messages = [...this.messages, message]
  }
  private palette(): PteIMUIThemePalette { return this.client === null ? (this.previewDark ? this.theme.dark : this.theme.light) : PteIMUITheme.resolve(this.client, this.theme, this.systemColorMode === 'dark') }
  private isDark(): boolean { return this.palette().background === '#0E111C' }
  private currentLanguage(): PteIMLanguage { return this.client === null ? this.previewLanguage : this.client.currentAppearance().language }
  private isEnglish(): boolean { return this.currentLanguage() === PteIMLanguage.EN_US }
  private isOutgoing(message: PteIMMessage): boolean { return message.senderId === (this.client === null ? this.previewUserId : this.client.currentUserId()) }
  private voiceSeconds(message: PteIMMessage): number { return Math.max(1, Math.floor((message.voice?.durationMs ?? 8000) / 1000)) }
  private videoDuration(message: PteIMMessage): string {
    const seconds = Math.max(1, Math.floor((message.media?.durationMs ?? 24000) / 1000))
    return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`
  }
  private fileSize(bytes: number): string { return `${Math.max(1, Math.round(bytes / 1024))} KB` }
  /** File metadata keeps contrast in both the purple outgoing bubble and an incoming surface. */
  private fileTitleColor(outgoing: boolean): string {
    if (outgoing) return this.isDark() ? '#F7F1FF' : '#FFFFFF'
    return this.isDark() ? '#F1F3FF' : '#20253A'
  }
  private fileSizeColor(outgoing: boolean): string {
    if (outgoing) return this.isDark() ? '#D9C8FF' : '#E8DCFF'
    return this.isDark() ? '#9FA9C6' : '#707991'
  }
  private richCardStatus(message: PteIMMessage): string {
    if (message.type === PteIMMessageType.RED_PACKET) return this.isEnglish() ? '✦ Claimed ✦' : '✦ 已领取 ✦'
    return this.isEnglish() ? '✦ Received ✦' : '✦ 已领取 ✦'
  }
  private isGroup(): boolean { return this.groupConversation || this.title.includes('Team') || this.title.includes('群') }
  private avatarForTitle(): string { const value = this.title.length > 0 ? this.title : this.conversationId; return value.substring(0, 1).toUpperCase() }
  private selectMessage(clientMsgId: string): void { this.selectedMessageId = this.selectedMessageId === clientMsgId ? '' : clientMsgId }
  /** A second tap on the same reaction cancels the local vote; the count cell vanishes at zero. */
  private toggleReaction(message: PteIMMessage, emoji: string): void {
    const index = this.localReactions.findIndex((item: PteIMUILocalReaction) => item.messageId === message.clientMsgId && item.emoji === emoji)
    const before = index >= 0 ? this.localReactions[index].addedByMe : this.reactionProvider.reactedByMe(message, emoji)
    const selected = !before
    const persisted = this.reactionProvider.reactedByMe(message, emoji)
    if (selected === persisted) this.localReactions = this.localReactions.filter((item: PteIMUILocalReaction) => !(item.messageId === message.clientMsgId && item.emoji === emoji))
    else if (index >= 0) {
      const updated = [...this.localReactions]
      updated[index] = new PteIMUILocalReaction(message.clientMsgId, emoji, selected)
      this.localReactions = updated
    } else this.localReactions = [...this.localReactions, new PteIMUILocalReaction(message.clientMsgId, emoji, selected)]
    this.operationHandler.react(message, emoji, selected)
    this.selectedMessageId = ''
  }
  /** Merges host-supplied reaction counts with this UI's current-user reaction. */
  private reactionValues(message: PteIMMessage): PteIMUIReaction[] {
    const values: PteIMUIReaction[] = []
    for (const reaction of this.reactionProvider.reactionsFor(message)) values.push(new PteIMUIReaction(reaction.emoji, reaction.count))
    for (const local of this.localReactions) {
      if (local.messageId !== message.clientMsgId) continue
      const index = values.findIndex((item: PteIMUIReaction) => item.emoji === local.emoji)
      const persisted = this.reactionProvider.reactedByMe(message, local.emoji)
      const delta = local.addedByMe === persisted ? 0 : (local.addedByMe ? 1 : -1)
      if (index >= 0) values[index] = new PteIMUIReaction(local.emoji, values[index].count + delta)
      else if (delta > 0) values.push(new PteIMUIReaction(local.emoji, 1))
    }
    return values.filter((item: PteIMUIReaction) => item.count > 0)
  }
  /** The plus button hands control to the input bar's emoji keyboard and closes this action card. */
  private openReactionEmoji(): void {
    this.selectedMessageId = ''
    this.emojiOpenSignal += 1
  }
  private deliveryIcon(message: PteIMMessage): Resource {
    const read = message.state === PteIMSendState.SENT && this.readReceiptProvider.isRead(message)
    return read ? (this.isDark() ? $r('app.media.PteIMUIChatReadDark') : $r('app.media.PteIMUIChatReadLight')) : (this.isDark() ? $r('app.media.PteIMUIChatUnreadDark') : $r('app.media.PteIMUIChatUnreadLight'))
  }
  private quoteMessage(message: PteIMMessage): void {
    this.quotedMessageId = message.clientMsgId
    this.quotedText = this.messageText(message)
    this.operationHandler.quote(message)
    this.selectedMessageId = ''
  }
  private async retryMessage(message: PteIMMessage): Promise<void> {
    if (this.client === null) {
      message.state = PteIMSendState.SENT
      this.messages = [...this.messages]
    } else {
      await this.client.retryMessage(message.clientMsgId)
      await this.loadMessages()
    }
  }
  private async revokeMessage(message: PteIMMessage): Promise<void> {
    this.operationHandler.revoke(message)
    if (this.client === null) this.messages = this.messages.filter((item: PteIMMessage) => item.clientMsgId !== message.clientMsgId)
    else { await this.client.deleteLocalMessage(message.clientMsgId); await this.loadMessages() }
    this.selectedMessageId = ''
  }
  private async deleteMessage(message: PteIMMessage): Promise<void> {
    this.operationHandler.delete(message)
    if (this.client === null) this.messages = this.messages.filter((item: PteIMMessage) => item.clientMsgId !== message.clientMsgId)
    else { await this.client.deleteLocalMessage(message.clientMsgId); await this.loadMessages() }
    this.selectedMessageId = ''
  }
  private presentation(message: PteIMMessage, outgoing: boolean): PteIMUIMessagePresentation {
    const time = `${new Date(message.createdAt).getHours().toString().padStart(2, '0')}:${new Date(message.createdAt).getMinutes().toString().padStart(2, '0')}`
    const value = new PteIMUIMessagePresentation(this.messageText(message), time, outgoing ? 'M' : this.avatarForTitle(), outgoing ? (this.isEnglish() ? 'Me' : '我') : (this.title.length > 0 ? this.title : this.conversationId))
    return this.presentationTransformer.transform(message, outgoing, value)
  }
  private isRich(message: PteIMMessage): boolean { return message.type === PteIMMessageType.IMAGE || message.type === PteIMMessageType.VIDEO || message.type === PteIMMessageType.LOCATION || message.type === PteIMMessageType.GIFT || message.type === PteIMMessageType.RED_PACKET || message.type === PteIMMessageType.ORDER || message.type === PteIMMessageType.FILE || message.type === PteIMMessageType.CUSTOM }
  private messageText(message: PteIMMessage): string {
    if (message.type === PteIMMessageType.TEXT) return message.text
    if (message.type === PteIMMessageType.EMOJI) return message.emojiId
    if (message.type === PteIMMessageType.IMAGE) return this.isEnglish() ? 'Photo' : '照片'
    if (message.type === PteIMMessageType.VIDEO) return this.isEnglish() ? 'Video' : '视频'
    if (message.type === PteIMMessageType.VOICE) return this.isEnglish() ? 'Voice' : '语音'
    if (message.type === PteIMMessageType.LOCATION) return message.location?.name ?? (this.isEnglish() ? 'Location' : '位置')
    if (message.type === PteIMMessageType.GIFT) return message.business?.title ?? (this.isEnglish() ? 'Gift' : '礼物')
    if (message.type === PteIMMessageType.RED_PACKET) return message.business?.title ?? (this.isEnglish() ? 'Red packet' : '红包')
    if (message.type === PteIMMessageType.ORDER) return message.business?.title ?? (this.isEnglish() ? 'Order' : '订单')
    if (message.type === PteIMMessageType.CUSTOM) return message.business?.title ?? (this.isEnglish() ? 'Custom message' : '自定义消息')
    return message.media?.fileName ?? (this.isEnglish() ? 'File' : '文件')
  }
}
