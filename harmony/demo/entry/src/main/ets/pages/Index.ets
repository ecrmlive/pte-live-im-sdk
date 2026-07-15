import { Context } from '@kit.AbilityKit'
import { PteIMBaseConfig, PteIMBusinessContent, PteIMLocation, PteIMLoginConfig, PteIMThemeMode, PteLiveIM } from '@ptelive/im'
import { PteIMUIAction, PteIMUIActionHandler, PteIMUIChat } from '@ptelive/im-ui-kit'

/** The demo only performs runtime configuration; its chat UI is the reusable PteIMUIKit component. */
@Entry
@Component
struct Index {
  @State apiDomain: string = 'https://api.example.com'
  @State imDomain: string = 'wss://im.example.com/ws'
  @State cosDomain: string = 'https://cos.example.com'
  @State sdkAppId: string = '1400000001'
  @State userId: string = '10001'
  @State userSig: string = ''
  @State conversationId: string = 'c2c:10001:10002'
  @State status: string = '未连接；不会保存 UserSig'
  @State chatVisible: boolean = false
  private client: PteLiveIM | null = null
  private actionHandler: PteIMUIActionHandler = new PteIMUIActionHandler((action: PteIMUIAction) => this.handleAction(action))

  build() {
    if (this.chatVisible && this.client !== null) {
      PteIMUIChat({ client: this.client as PteLiveIM, conversationId: this.conversationId, title: 'PteIMUIKit · HarmonyOS', actionHandler: this.actionHandler })
    } else {
      Scroll() {
        Column({ space: 10 }) {
          Text('PteIMUIKit · HarmonyOS').fontSize(24).fontColor('#1769AA').fontWeight(FontWeight.Bold)
          Text('登录完成后直接展示 HAR 提供的 PteIMUIChat。').fontSize(13).fontColor('#666666')
          this.input('API domain', this.apiDomain, (value: string) => this.apiDomain = value)
          this.input('IM WSS URL', this.imDomain, (value: string) => this.imDomain = value)
          this.input('COS domain', this.cosDomain, (value: string) => this.cosDomain = value)
          this.input('SDK App ID', this.sdkAppId, (value: string) => this.sdkAppId = value)
          this.input('Numeric user ID', this.userId, (value: string) => this.userId = value)
          TextInput({ placeholder: 'UserSig', text: this.userSig }).type(InputType.Password).onChange((value: string) => this.userSig = value).width('100%')
          this.input('Conversation ID', this.conversationId, (value: string) => this.conversationId = value)
          Button('连接并打开 PteIMUIKit').onClick(() => this.connect()).width('100%')
          Text(this.status).fontColor('#1769AA')
        }.width('100%').padding(18)
      }
    }
  }

  @Builder input(placeholder: string, value: string, change: (value: string) => void) { TextInput({ placeholder: placeholder, text: value }).onChange(change).width('100%') }
  private async connect(): Promise<void> {
    try {
      const context = AppStorage.get<Context>('pteDemoContext')
      if (context === undefined) throw new Error('Ability context is unavailable')
      const base = new PteIMBaseConfig(this.apiDomain, this.imDomain, this.cosDomain, PteIMThemeMode.SYSTEM)
      this.client?.stop()
      this.client = await PteLiveIM.configure(context, base).login(new PteIMLoginConfig(Number(this.sdkAppId), this.userId, this.userSig))
      this.chatVisible = true
    } catch (error) { this.status = `配置错误：${(error as Error).message}` }
  }
  private handleAction(action: PteIMUIAction): void {
    const client = this.client
    if (client === null) return
    if (action === PteIMUIAction.LOCATION) client.sendLocation(this.conversationId, new PteIMLocation(31.2304, 121.4737, 'Shanghai', 'PteIMUIKit demo'))
    else if (action === PteIMUIAction.GIFT) client.sendGift(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo gift'))
    else if (action === PteIMUIAction.RED_PACKET) client.sendRedPacket(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo red packet'))
    else if (action === PteIMUIAction.ORDER) client.sendOrder(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo order'))
    // IMAGE / VIDEO / VOICE: obtain a file path with the host picker, then call uploadAndSend*.
  }
}
