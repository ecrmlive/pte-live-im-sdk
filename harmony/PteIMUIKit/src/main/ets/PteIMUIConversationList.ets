import { PteIMConversation, PteIMListener, PteIMMessage, PteIMSendState, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUIConversationHandler } from './PteIMUIKit'

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
  demo: boolean

  constructor(id: string, title: string, preview: string, time: string, avatar: string, color: string, unread: number = 0, online: boolean = false, demo: boolean = false) {
    this.id = id
    this.title = title
    this.preview = preview
    this.time = time
    this.avatar = avatar
    this.color = color
    this.unread = unread
    this.online = online
    this.demo = demo
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
  @Prop presentationTransformer: PteIMUIConversationPresentationTransformer = new PteIMUIConversationPresentationTransformer()
  @State conversations: PteIMConversation[] = []
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
        Stack({ alignContent: Alignment.BottomEnd }) {
          Text(item.avatar).width(44).height(44).textAlign(TextAlign.Center).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White).backgroundColor(item.color).borderRadius(22)
          if (item.online) Circle({ width: 10, height: 10 }).fill('#12C96B')
        }.width(44).height(44)
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

  private async load(): Promise<void> { this.conversations = this.client === null ? [] : await this.client.localConversations() }
  private async refresh(): Promise<void> {
    this.refreshing = true
    try { await this.load() } finally { this.refreshing = false }
  }

  private items(): PteIMUIConversationPresentation[] {
    const query = this.query.trim().toLowerCase()
    const base = this.conversations.length === 0 ? this.demoItems() : this.localItems()
    const transformed = base.map((item: PteIMUIConversationPresentation) => this.presentationTransformer.transform(item))
    if (query.length === 0) return transformed
    return transformed.filter((item: PteIMUIConversationPresentation) => item.title.toLowerCase().includes(query) || item.preview.toLowerCase().includes(query))
  }

  private demoItems(): PteIMUIConversationPresentation[] {
    return [
      new PteIMUIConversationPresentation('demo-alice', 'Alice Chen', this.english ? 'See you tomorrow!' : '明天见！See you tomorrow!', '10:24', 'A', '#8B4AF5', 2, true, true),
      new PteIMUIConversationPresentation('demo-work', 'Work Team 工作群', this.english ? '[Image]' : '[图片] [Image]', '09:51', '#', '#07A5C7', 5, false, true),
      new PteIMUIConversationPresentation('demo-bob', 'Bob Li', this.english ? '[Voice] 12s' : '[语音] 12秒', this.english ? 'Yesterday' : '昨天', 'B', '#06A46F', 0, false, true),
      new PteIMUIConversationPresentation('demo-alpha', 'Project Alpha', this.english ? 'Got it' : '收到，我来处理 Got it', this.english ? 'Yesterday' : '昨天', '#', '#ED8700', 0, false, true),
      new PteIMUIConversationPresentation('demo-carol', 'Carol Wu', this.english ? '[Red packet] Congratulations!' : '[红包] 恭喜发财', this.english ? 'Mon' : '周一', 'C', '#DB2972', 0, true, true),
      new PteIMUIConversationPresentation('demo-dave', 'Dave Zhang', this.english ? '[Order] iPhone 15 Pro' : '[订单] iPhone 15 Pro', this.english ? 'Sun' : '周日', 'D', '#7334EE', 0, false, true)
    ]
  }

  private localItems(): PteIMUIConversationPresentation[] {
    const colors = ['#8B4AF5', '#07A5C7', '#06A46F', '#ED8700', '#DB2972', '#7334EE']
    return this.conversations.map((item: PteIMConversation, index: number) => new PteIMUIConversationPresentation(item.conversationId, item.conversationId, this.preview(item), this.time(item.updatedAt), this.avatarText(item.conversationId), colors[index % colors.length], 0, false, false))
  }

  // Demo rows use the same navigation callback, so a token-free integration can still
  // open its preview chat instead of leaving the list visually interactive but inert.
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
