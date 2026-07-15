import { Context } from '@kit.AbilityKit'
import { PteIMBaseConfig, PteIMBusinessContent, PteIMLocation, PteIMLoginConfig, PteIMThemeMode, PteIMSDK } from '@ptelive/pte-im-sdk'
import { PteIMUIAction, PteIMUIActionHandler, PteIMUIChat, PteIMUIConversationHandler, PteIMUIConversationList } from '@ptelive/pte-im-uikit'

/** Business sample: business authentication returns a userId/UserSig, then PteIMSDK logs in and PteIMUIkit renders IM. */
@Entry
@Component
struct Index {
  @State apiDomain: string = 'https://api.example.com'
  @State imDomain: string = 'wss://im.example.com/ws'
  @State cosDomain: string = 'https://cos.example.com'
  @State sdkAppId: string = '1400000001'
  @State account: string = 'demo-user'
  @State password: string = ''
  @State userId: string = '10001'
  @State userSig: string = ''
  @State conversationId: string = ''
  @State status: string = '未登录；不会保存 UserSig'
  @State screen: string = 'login'
  private client: PteIMSDK | null = null
  private actionHandler: PteIMUIActionHandler = new PteIMUIActionHandler((action: PteIMUIAction) => this.handleAction(action))
  private conversationHandler: PteIMUIConversationHandler = new PteIMUIConversationHandler((conversationId: string) => { this.conversationId = conversationId; this.screen = 'chat' })

  build() {
    if (this.screen === 'chat' && this.client !== null) {
      PteIMUIChat({ client: this.client as PteIMSDK, conversationId: this.conversationId, title: 'PteIMUIDemo', actionHandler: this.actionHandler })
    } else if (this.screen === 'conversations' && this.client !== null) {
      PteIMUIConversationList({ client: this.client as PteIMSDK, conversationHandler: this.conversationHandler })
    } else if (this.screen === 'home') {
      this.businessHome()
    } else if (this.screen === 'friends') {
      this.friendList()
    } else if (this.screen === 'profile') {
      this.profile()
    } else {
      this.businessLogin()
    }
  }

  @Builder businessLogin() {
    Scroll() { Column({ space: 10 }) {
      Text('PteIMUIDemo · HarmonyOS').fontSize(24).fontColor('#1769AA').fontWeight(FontWeight.Bold)
      Text('业务登录 → 后端返回 IM userId/UserSig → PteIMSDK 登录 → PteIMUIkit。请替换示例输入为您的业务登录 API。').fontSize(13).fontColor('#666666')
      this.input('API domain', this.apiDomain, (value: string) => this.apiDomain = value)
      this.input('IM WSS URL', this.imDomain, (value: string) => this.imDomain = value)
      this.input('COS domain', this.cosDomain, (value: string) => this.cosDomain = value)
      this.input('SDK App ID', this.sdkAppId, (value: string) => this.sdkAppId = value)
      this.input('Business account', this.account, (value: string) => this.account = value)
      TextInput({ placeholder: 'Business password (demo only)', text: this.password }).type(InputType.Password).onChange((value: string) => this.password = value).width('100%')
      this.input('IM user ID returned by business login', this.userId, (value: string) => this.userId = value)
      TextInput({ placeholder: 'Short-lived UserSig returned by business login', text: this.userSig }).type(InputType.Password).onChange((value: string) => this.userSig = value).width('100%')
      Button('业务登录并进入 IM').onClick(() => this.connect()).width('100%')
      Text(this.status).fontColor('#1769AA')
    }.width('100%').padding(18) }
  }

  @Builder businessHome() {
    Column({ space: 12 }) {
      Text('PteIMUIDemo').fontSize(24).fontColor('#1769AA').fontWeight(FontWeight.Bold)
      Text('业务层：好友关系、我的；IM UI：会话、聊天、群组。').fontSize(13).fontColor('#666666')
      Button('会话列表（PteIMUIkit）').onClick(() => this.screen = 'conversations').width('100%')
      Button('好友列表 / 关系').onClick(() => this.screen = 'friends').width('100%')
      Button('创建群组并聊天（PteIMUIkit）').onClick(() => { this.openDemoGroupChat() }).width('100%')
      Button('我的').onClick(() => this.screen = 'profile').width('100%')
      Button('退出登录').onClick(() => { this.client?.stop(); this.client = null; this.screen = 'login' }).width('100%')
    }.width('100%').padding(18)
  }

  @Builder friendList() {
    Column({ space: 12 }) {
      Text('好友列表 / 关系示例').fontSize(22).fontWeight(FontWeight.Bold)
      Text('添加、删除好友由业务 API 完成；PteIMUIkit 负责聊天界面。').fontSize(13).fontColor('#666666')
      Button('Alice (10002)').onClick(() => { this.openSingleChat(10002, 'Alice') }).width('100%')
      Button('Bob (10003)').onClick(() => { this.openSingleChat(10003, 'Bob') }).width('100%')
      Button('返回').onClick(() => this.screen = 'home').width('100%')
    }.width('100%').padding(18)
  }

  @Builder profile() {
    Column({ space: 12 }) {
      Text('我的').fontSize(22).fontWeight(FontWeight.Bold)
      Text(`业务账号：${this.account}\nIM 用户：${this.userId}\n\n个人资料、好友关系、主题和语言均由业务 App 管理；调用 PteIMSDK.updateAppearance(...) 可即时更新 UI。`).fontSize(14)
      Button('返回').onClick(() => this.screen = 'home').width('100%')
    }.width('100%').padding(18)
  }

  @Builder input(placeholder: string, value: string, change: (value: string) => void) { TextInput({ placeholder: placeholder, text: value }).onChange(change).width('100%') }
  private async connect(): Promise<void> {
    try {
      if (this.account.length === 0 || this.userId.length === 0 || this.userSig.length === 0) throw new Error('业务后端应返回 account、userId 与短期 UserSig')
      const context = AppStorage.get<Context>('pteDemoContext')
      if (context === undefined) throw new Error('Ability context is unavailable')
      const base = new PteIMBaseConfig(this.apiDomain, this.imDomain, this.cosDomain, PteIMThemeMode.SYSTEM)
      this.client?.stop()
      this.client = await PteIMSDK.configure(context, base).login(new PteIMLoginConfig(Number(this.sdkAppId), this.userId, this.userSig))
      this.screen = 'home'
    } catch { this.status = '登录错误：请检查业务登录返回的域名、userId 和 UserSig' }
  }
  /** The service creates C2C/group rows and returns the only valid numeric conversation ID. */
  private async openSingleChat(peerUserId: number, _title: string): Promise<void> {
    const client = this.client
    if (client === null) return
    try {
      const conversation = await client.openSingleConversation(peerUserId)
      this.conversationId = conversation.id.toString()
      this.screen = 'chat'
    } catch { this.status = '无法打开会话：请检查好友关系和 IM 服务状态' }
  }
  private async openDemoGroupChat(): Promise<void> {
    const client = this.client
    if (client === null) return
    try {
      const conversation = await client.createGroupConversation('PteIMUIDemo Group', [10002, 10003])
      this.conversationId = conversation.id.toString()
      this.screen = 'chat'
    } catch { this.status = '无法创建群组：请检查业务成员关系和 IM 服务状态' }
  }
  private handleAction(action: PteIMUIAction): void {
    const client = this.client
    if (client === null) return
    if (action === PteIMUIAction.LOCATION) client.sendLocation(this.conversationId, new PteIMLocation(31.2304, 121.4737, 'Shanghai', 'PteIMUIDemo'))
    else if (action === PteIMUIAction.GIFT) client.sendGift(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo gift'))
    else if (action === PteIMUIAction.RED_PACKET) client.sendRedPacket(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo red packet'))
    else if (action === PteIMUIAction.ORDER) client.sendOrder(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo order'))
    // IMAGE / VIDEO / VOICE: the host selects a local file, then calls uploadAndSend*.
  }
}
