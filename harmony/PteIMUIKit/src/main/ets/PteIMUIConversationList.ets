import { PteIMConversation, PteIMListener, PteIMMessage, PteIMRemoteConversation, PteIMSendState, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUIConversationHandler } from './PteIMUIKit'
import { PteIMUIAvatar } from './PteIMUIAvatar'

class PteIMUIConversationListener extends PteIMListener {
  private readonly changed: () => void
  constructor(changed: () => void) { super(); this.changed = changed }
  onMessage(_message: PteIMMessage): void { this.changed() }
  onMessageStateChanged(_clientMsgId: string, _state: PteIMSendState): void { this.changed() }
}

/** Public row model. Hosts may derive a transformer and replace any display field. */
export class PteIMUIConversationPresentation {
  id: string
  title: string
  preview: string
  time: string
  avatar: string
  color: string
  unread: number
  online: boolean
  /** Remote avatar URL. It is rendered with ImageFit.Cover inside the circular clip. */
  avatarURL: string

  constructor(id: string, title: string, preview: string, time: string, avatar: string, color: string, unread: number = 0, online: boolean = false, avatarURL: string = '') {
    this.id = id
    this.title = title
    this.preview = preview
    this.time = time
    this.avatar = avatar
    this.color = color
    this.unread = unread
    this.online = online
    this.avatarURL = avatarURL
  }
}

/**
 * MessageKit-style display extension point. Subclass and override transform()
 * to rewrite conversation title, preview, time, avatar, unread state, or order
 * without changing Core's cache or paging behaviour.
 */
export class PteIMUIConversationPresentationTransformer {
  transform(value: PteIMUIConversationPresentation): PteIMUIConversationPresentation { return value }
}

/** Conversation screen matching the supplied light and dark mobile visual specs. */
@Component
export struct PteIMUIConversationList {
  @Prop client: PteIMSDK | null = null
  @Prop conversationHandler: PteIMUIConversationHandler = new PteIMUIConversationHandler()
  @Prop dark: boolean = false
  @Prop english: boolean = true
  /** Negative keeps the default circle; set vp to customise list avatars. */
  @Prop avatarCornerRadius: number = -1
  @Prop presentationTransformer: PteIMUIConversationPresentationTransformer = new PteIMUIConversationPresentationTransformer()
  @State conversations: PteIMConversation[] = []
  @State remoteConversations: PteIMRemoteConversation[] = []
  @State query: string = ''
  @State refreshing: boolean = false
  private listener: PteIMUIConversationListener | null = null

  aboutToAppear(): void {
    if (this.client === null) { this.conversations = []; return }
    this.listener = new PteIMUIConversationListener(() => this.load())
    this.client.addListener(this.listener)
    this.load()
  }

  aboutToDisappear(): void {
    if (this.listener !== null && this.client !== null) this.client.removeListener(this.listener)
  }

  build() {
    Column() {
      this.navigationBar()
      this.searchBox()
      Refresh({ refreshing: $$this.refreshing, offset: 64, friction: 62 }) {
        List() {
          ForEach(this.items(), (item: PteIMUIConversationPresentation) => {
            ListItem() { this.conversationRow(item) }.onClick(() => this.select(item))
          }, (item: PteIMUIConversationPresentation) => item.id)
        }.height('100%').width('100%').backgroundColor(this.pageBg()).scrollBar(BarState.Off)
      }.layoutWeight(1).width('100%').backgroundColor(this.pageBg()).onRefreshing(() => this.refresh())
    }.width('100%').height('100%').backgroundColor(this.pageBg())
  }

  @Builder private navigationBar() {
    Row() {
      Row({ space: 8 }) {
        Image($r('app.media.PteIMUIConversationLogo')).width(28).height(28)
        Text(this.english ? 'Chats' : '会话').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.textColor())
      }.layoutWeight(1)
      Image(this.dark ? $r('app.media.PteIMUIConversationCreateDark') : $r('app.media.PteIMUIConversationCreateLight')).width(44).height(44).padding(10)
    }.width('100%').height(44).padding({ left: 20, right: 20 }).backgroundColor(this.headerColor())
  }

  @Builder private searchBox() {
    Row({ space: 8 }) {
      Image($r('app.media.PteIMUIConversationSearch')).width(18).height(18)
      TextInput({ placeholder: this.english ? 'Search' : '搜索', text: this.query }).layoutWeight(1).fontSize(14).fontColor(this.textColor()).placeholderColor(this.mutedColor()).backgroundColor(Color.Transparent).onChange((value: string) => this.query = value)
    }.width('auto').height(40).margin({ left: 20, right: 20, top: 6, bottom: 12 }).padding({ left: 14, right: 14 }).backgroundColor(this.searchColor()).border({ width: 1, color: this.searchBorderColor(), radius: 14 })
  }

  @Builder private conversationRow(item: PteIMUIConversationPresentation) {
    Column() {
      Row({ space: 12 }) {
        PteIMUIAvatar({ url: item.avatarURL, label: item.avatar, avatarSize: 44, cornerRadius: this.avatarCornerRadius, fillColor: item.color, online: item.online })
        Column({ space: 4 }) {
          Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.textColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
          Text(item.preview).fontSize(12).fontColor(this.mutedColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').textAlign(TextAlign.Start)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 7 }) {
          Text(item.time).fontSize(11).fontColor(this.mutedColor()).textAlign(TextAlign.End).width('100%')
          // Badge is visually anchored 5vp farther right than its time column, matching the conversation artboard.
          if (item.unread > 0) Text(item.unread.toString()).fontSize(10).fontWeight(FontWeight.Medium).fontColor(Color.White).textAlign(TextAlign.Center).width(18).height(18).backgroundColor('#F02B38').borderRadius(9).alignSelf(ItemAlign.End).translate({ x: 5 })
        }.width(52).alignItems(HorizontalAlign.End)
      }.width('100%').height(72).padding({ left: 20, right: 20 }).backgroundColor(this.pageBg())
      Row() {
        Blank().width(76)
        Blank().layoutWeight(1).height(1).backgroundColor(this.dividerColor())
        Blank().width(20)
      }.height(1).width('100%')
    }.width('100%').height(73).backgroundColor(this.pageBg())
  }

  private async load(): Promise<void> {
    if (this.client === null) { this.conversations = []; this.remoteConversations = []; return }
    this.conversations = await this.client.localConversations()
    this.remoteConversations = await this.client.localRemoteConversations()
  }
  private async refresh(): Promise<void> {
    this.refreshing = true
    try { await this.load() } finally { this.refreshing = false }
  }

  private items(): PteIMUIConversationPresentation[] {
    const query = this.query.trim().toLowerCase()
    const base = this.localItems()
    const transformed = base.map((item: PteIMUIConversationPresentation) => this.presentationTransformer.transform(item))
    if (query.length === 0) return transformed
    return transformed.filter((item: PteIMUIConversationPresentation) => item.title.toLowerCase().includes(query) || item.preview.toLowerCase().includes(query))
  }

  private localItems(): PteIMUIConversationPresentation[] {
    const colors = ['#8B4AF5', '#07A5C7', '#06A46F', '#ED8700', '#DB2972', '#7334EE']
    return this.conversations.map((item: PteIMConversation, index: number) => {
      const remote = this.remoteConversations.find((value: PteIMRemoteConversation) => value.id.toString() === item.conversationId)
      const title = remote !== undefined && remote.title.length > 0 ? remote.title : item.conversationId
      return new PteIMUIConversationPresentation(item.conversationId, title, this.preview(item), this.time(item.updatedAt), this.avatarText(title), colors[index % colors.length], remote?.unreadCount ?? 0, false, remote?.avatar ?? '')
    })
  }

  private select(item: PteIMUIConversationPresentation): void { this.conversationHandler.select(item.id, item.title) }
  private preview(item: PteIMConversation): string { if (item.lastMessage.type === 'text') return item.lastMessage.text; if (item.lastMessage.type === 'image') return this.english ? '[Image]' : '[图片]'; if (item.lastMessage.type === 'voice') return this.english ? '[Voice]' : '[语音]'; return `[${item.lastMessage.type}]` }
  private avatarText(value: string): string { return value.length > 0 ? value.substring(0, 1).toUpperCase() : '?' }
  private time(value: number): string { const date = new Date(value); return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}` }
  private pageBg(): string { return this.dark ? '#07071C' : '#F1F1FF' }
  private headerColor(): string { return this.dark ? '#12112E' : '#FFFFFF' }
  private searchColor(): string { return this.dark ? '#211E4C' : '#E4E1F8' }
  private searchBorderColor(): string { return this.dark ? '#211E4C' : '#CEC8EC' }
  private textColor(): string { return this.dark ? '#F1F0FF' : '#25233F' }
  private mutedColor(): string { return this.dark ? '#9A98B7' : '#76758F' }
  private dividerColor(): string { return this.dark ? '#35315C' : '#D4D0EC' }
}
