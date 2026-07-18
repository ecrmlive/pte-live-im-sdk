import { PteIMBusinessContent, PteIMLocation, PteIMLoginConfig, PteIMMedia, PteIMMessage, PteIMMessageType, PteIMSDK, PteIMSDKBootstrap, PteIMSendState, PteIMThemeMode, PteIMLanguage, PteIMVoice, PteIMResponseCrypto } from '@ptelive/pte-im-sdk'
import { PteIMUIAction, PteIMUIActionHandler, PteIMUIChat, PteIMUIChatNavigationHandler, PteIMUIConversationHandler, PteIMUIConversationList, PteIMUINavigationBackHandler, PteIMUINavigationBar, PteIMUINavigationHandler, PteIMUINotice, PteIMUINoticeDismissHandler, PteIMUINoticeHandler, PteIMUINoticeKind, PteIMUINoticePosition } from '@ptelive/pte-im-uikit'
import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { i18n } from '@kit.LocalizationKit'
import { drawing } from '@kit.ArkGraphics2D'
import { window } from '@kit.ArkUI'
import http from '@ohos.net.http'

class DemoAuthRequest {
  mobile: string = ''
  nickname: string = ''
  password: string = ''
  captcha_id: string = ''
  captcha_code: string = ''
  device_id: string = ''
  platform: string = ''
}

class DemoFriendRequest {
  target_user_id: string = ''
}

class DemoCaptchaResponse {
  captcha_id: string = ''
  image_data: string = ''
}

class DemoAuthResponse {
  sdk_app_id: string = ''
  user_id: string = ''
  user_sig: string = ''
}

class DemoUserResponse {
  user_id: string = ''
  nickname: string = ''
  mobile: string = ''
}

interface DemoHttpRequestOptions extends http.HttpRequestOptions {}

/** App-level domains are configured in EntryAbility. Login receives only business-issued IM credentials. */
@Entry
@Component
struct Index {
  @State sdkAppId: string = '432532532'
  @State userId: string = '123654'
  @State userSig: string = ''
  @State mobile: string = ''
  @State nickname: string = ''
  @State password: string = ''
  @State captchaID: string = ''
  @State captchaCode: string = ''
  @State captchaImage: string = ''
  @State demoUserNames: string[] = []
  @State demoUserIDs: string[] = []
  @State conversationId: string = ''
  @State chatTitle: string = ''
  @State chatIsGroup: boolean = false
  @State previewConversationId: string = 'preview-work'
  @State previewChatTitle: string = 'Work Team 工作群'
  @State previewChatIsGroup: boolean = true
  @State noticeVisible: boolean = false
  @State noticeMessage: string = ''
  @State noticeKind: PteIMUINoticeKind = PteIMUINoticeKind.SUCCESS
  @State noticePosition: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM
  @State noticeDuration: number = 2600
  @State noticeRevision: number = 0
  // 真实演示默认从业务注册/登录进入，再使用服务端签发的 UserSig 连接 IM。
  @State screen: string = 'login'
  @State showingStartup: boolean = true
  @State darkMode: boolean = this.isAutomaticDarkMode()
  @State english: boolean = this.isSystemEnglish()
  @State themePreference: string = 'auto'
  @State languagePreference: string = 'system'
  @State notificationsOn: boolean = true
  @State soundOn: boolean = true
  @State readReceiptsOn: boolean = true
  private chatReturnScreen: string = 'conversations'
  private client: PteIMSDK | null = null
  private appearanceStore: preferences.Preferences | null = null
  private appearanceTimer: number = -1
  private startupTimer: number = -1
  private noticeHandler: PteIMUINoticeHandler = new PteIMUINoticeHandler((notice) => {
    this.noticeMessage = notice.message
    this.noticeKind = notice.kind
    this.noticePosition = notice.position
    this.noticeDuration = notice.duration
    this.noticeVisible = true
    this.noticeRevision++
  })
  private noticeDismissHandler: PteIMUINoticeDismissHandler = new PteIMUINoticeDismissHandler(() => this.noticeVisible = false)
  private actionHandler: PteIMUIActionHandler = new PteIMUIActionHandler((action: PteIMUIAction) => this.handleAction(action))
  private conversationHandler: PteIMUIConversationHandler = new PteIMUIConversationHandler((conversationId: string, title: string) => {
    if (this.client === null) {
      this.openPreviewChat(conversationId, title, 'conversations')
      return
    }
    this.chatReturnScreen = 'conversations'
    this.conversationId = conversationId
    this.chatTitle = title
    this.chatIsGroup = this.isGroupTitle(title)
    this.setScreen('chat')
  })
  private chatNavigationHandler: PteIMUIChatNavigationHandler = new PteIMUIChatNavigationHandler(() => this.setScreen(this.chatReturnScreen))
  private navigationHandler: PteIMUINavigationHandler = new PteIMUINavigationHandler((language: PteIMLanguage) => this.applyLanguage(language), (theme: PteIMThemeMode) => this.applyTheme(theme))
  private registrationBackHandler: PteIMUINavigationBackHandler = new PteIMUINavigationBackHandler(() => {
    this.noticeVisible = false
    this.setScreen('login')
  })

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        if (this.screen === 'chatPreview') this.chatPreview()
        else if (this.screen === 'login') this.businessLogin(false)
        else if (this.screen === 'register') this.businessLogin(true)
        else if (this.screen === 'demoUsers') this.demoUsersPage()
        else if (this.screen === 'chat' && this.client !== null) PteIMUIChat({ client: this.client as PteIMSDK, conversationId: this.conversationId, title: this.chatTitle, groupConversation: this.chatIsGroup, actionHandler: this.actionHandler, navigationHandler: this.chatNavigationHandler })
        else if (this.screen === 'settings') this.settingsPage()
        else if (this.screen === 'languageSettings') this.languageSettingsPage()
        else this.businessShell()
      }.width('100%').height('100%').backgroundColor(this.darkMode ? '#0E0F1F' : '#F4F4FF')
      if (this.showingStartup) this.startupPage()
      if (this.noticeVisible) PteIMUINotice({
        visible: this.noticeVisible,
        message: this.noticeMessage,
        kind: this.noticeKind,
        noticePosition: this.noticePosition,
        dark: this.darkMode,
        duration: this.noticeDuration,
        revision: this.noticeRevision,
        dismissHandler: this.noticeDismissHandler,
      })
    }.width('100%').height('100%').backgroundColor(this.darkMode ? '#0E111C' : '#F4F4FF').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  aboutToAppear(): void {
    this.restoreAppearancePreferences()
    this.applySystemBarStyle()
    this.startupTimer = setTimeout(() => { this.showingStartup = false; this.applySystemBarStyle() }, 900)
    this.appearanceTimer = setInterval(() => this.refreshAutomaticAppearance(), 60 * 1000)
    void this.loadCaptcha()
  }

  aboutToDisappear(): void {
    if (this.appearanceTimer !== -1) clearInterval(this.appearanceTimer)
    if (this.startupTimer !== -1) clearTimeout(this.startupTimer)
  }

  @Builder startupPage() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {}.width('100%').height('100%').backgroundColor('#0B061B')
      Image($r('app.media.PteIMUIStartupBackground')).width('100%').height('100%').objectFit(ImageFit.Cover)
      Image($r('app.media.PteIMUIStartup')).width('100%').height('100%').objectFit(ImageFit.Contain)
    }.width('100%').height('100%')
  }

  /** Opens immediately so the complete chat surface can be inspected without committing a UserSig. */
  @Builder chatPreview() {
    PteIMUIChat({
      client: null,
      conversationId: this.previewConversationId,
      title: this.previewChatTitle,
      groupConversation: this.previewChatIsGroup,
      navigationSubtitleText: this.previewChatIsGroup ? (this.english ? '8 members' : '8位成员') : (this.english ? 'Online' : '在线'),
      // The token-free preview has a real return destination: the built-in demo conversation list.
      navigationHandler: new PteIMUIChatNavigationHandler(() => this.setScreen(this.chatReturnScreen)),
      previewMessages: this.demoChatMessages(),
      previewUserId: 'demo-me',
      previewDark: this.darkMode,
      previewLanguage: this.english ? PteIMLanguage.EN_US : PteIMLanguage.ZH_CN,
    })
  }

  /** Registration is rendered as an independent page, never a login-field toggle. */
  @Builder businessLogin(register: boolean) {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column() {
          // Match the Android artboard: the fixed navigation sits above a deliberately quiet brand area.
          Blank().height(138)
          Column() {
            Image($r('app.media.PteIMUILogo')).width(103).height(103)
            Text('PrivateChat').fontSize(29).fontWeight(FontWeight.Bold).fontColor(this.darkMode ? '#F0EDFF' : '#17182B').margin({ top: 34 })
            Text('Secure · Private · Efficient').fontSize(14).fontColor(this.darkMode ? '#A69FC7' : '#656982').margin({ top: 12 })
          }.width('100%').alignItems(HorizontalAlign.Center).margin({ top: 7, bottom: this.darkMode ? 19 : 31 })
          Column() {
            this.formLabel(this.english ? 'Mobile' : '手机号')
            this.formInput(this.english ? 'Mobile (+86 or international)' : '手机号（中国或国际）', this.mobile, (value: string) => this.mobile = value, InputType.PhoneNumber)
            if (register) {
              this.formLabel(this.english ? 'Nickname' : '昵称')
              this.formInput(this.english ? 'Nickname (required to register)' : '昵称（注册必填）', this.nickname, (value: string) => this.nickname = value, InputType.Normal)
            }
            this.formLabel(this.english ? 'Password' : '密码')
            TextInput({ placeholder: this.english ? 'Password' : '密码', text: this.password }).type(InputType.Password).height(46).fontSize(15).fontColor(this.darkMode ? '#F0EDFF' : '#17182B').placeholderColor(this.darkMode ? '#A69FC7' : '#656982').backgroundColor(this.darkMode ? '#201E4C' : '#EDE9FF').borderRadius(18).padding({ left: 16, right: 16 }).onChange((value: string) => this.password = value).width('100%')
            this.formLabel(this.english ? 'Verification code' : '图形验证码')
            Row({ space: 10 }) {
              Column() { this.formInput(this.english ? 'Code' : '验证码', this.captchaCode, (value: string) => this.captchaCode = value, InputType.Number) }.layoutWeight(1)
              if (this.captchaImage.length > 0) Image(this.captchaImage).width(132).height(46).objectFit(ImageFit.Contain).onClick(() => { void this.loadCaptcha() })
              else Button(this.english ? 'Load' : '加载').width(132).height(46).onClick(() => { void this.loadCaptcha() })
            }.width('100%')
            Blank().height(24)
            Button() {
              Row({ space: 10 }) {
                Image($r('app.media.PteIMUILoginIcon')).width(18).height(18)
                Text(register ? (this.english ? 'Register' : '注册') : (this.english ? 'Login' : '登录')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
              }.justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center).width('100%')
            }.height(50).width('100%').borderRadius(18).linearGradient({ direction: GradientDirection.Right, colors: this.darkMode ? [['#8F57F5', 0.0], ['#8B4FEC', 1.0]] : [['#8B36F0', 0.0], ['#7130E0', 1.0]] }).onClick(() => { void this.authenticate(register) })
            if (!register) Button(this.english ? 'Create demo account' : '注册演示账号').type(ButtonType.Normal).height(46).width('100%').fontColor(this.darkMode ? '#F0EDFF' : '#7130E0').backgroundColor(Color.Transparent).onClick(() => this.setScreen('register'))
          }.width('100%').padding({ left: 24, top: 26, right: 24, bottom: 24 }).backgroundColor(this.darkMode ? '#11102A' : Color.White).border({ width: 1, color: this.darkMode ? '#39345A' : Color.Transparent, radius: 24 }).shadow({ radius: this.darkMode ? 0 : 18, color: '#22000000', offsetX: 0, offsetY: 8 })
        }.width('100%').alignItems(HorizontalAlign.Center).padding({ left: 30, right: 30, top: 12, bottom: 28 })
      }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(this.darkMode ? '#0D0D21' : '#F4F4FF')
      if (register) PteIMUINavigationBar({ title: '', language: this.selectedLanguage(), dark: this.darkMode, showBack: true, handler: this.navigationHandler, backHandler: this.registrationBackHandler })
      else PteIMUINavigationBar({ language: this.selectedLanguage(), dark: this.darkMode, handler: this.navigationHandler })
    }.width('100%').height('100%')
  }

  @Builder businessShell() {
    Column() {
      if (this.screen === 'conversations') PteIMUIConversationList({ client: this.client, conversationHandler: this.conversationHandler, dark: this.darkMode, english: this.english }).layoutWeight(1)
      else if (this.screen === 'contacts') this.contacts()
      else this.profile()
      if (this.isRootScreen()) this.tabs()
    }.width('100%').height('100%')
  }

  @Builder contacts() {
    Column() {
      this.contactsHeader()
      // Primary contact actions stay available while the address book scrolls underneath.
      Row({ space: 12 }) {
        this.contactQuickAction($r('app.media.PteIMUIContactAddFriend'), this.english ? 'Add Friend' : '添加好友', () => { void this.openDemoUsers() })
        this.contactQuickAction($r('app.media.PteIMUIContactNewGroup'), this.english ? 'New Group' : '发起群聊', () => this.openDemoGroupChat())
      }.width('100%').padding({ left: 20, right: 20, top: 14, bottom: 14 }).backgroundColor(this.pageColor())
      Scroll() {
        Column() {
          this.contactSectionTitle(this.english ? 'PERSONAL' : '个人')
          this.contactRow('A', 'Alice Chen', this.english ? '在线 · Online' : '在线 · Online', '#8B4AF5', true, () => this.openSingleChat(10002, 'Alice Chen'))
          this.contactRow('B', 'Bob Li', this.english ? 'Today 10:30' : '今天10:30', '#06A46F', false, () => this.openSingleChat(10003, 'Bob Li'))
          this.contactRow('C', 'Carol Wu', this.english ? '在线 · Online' : '在线 · Online', '#DB2972', true, () => this.openSingleChat(10004, 'Carol Wu'))
          this.contactRow('D', 'Dave Zhang', this.english ? 'Yesterday' : '昨天', '#7334EE', false, () => this.openSingleChat(10005, 'Dave Zhang'))
          this.contactRow('E', 'Eve Wang', this.english ? '在线 · Online' : '在线 · Online', '#E58400', true, () => this.openSingleChat(10006, 'Eve Wang'))
          this.contactRow('F', 'Frank Sun', this.english ? '3 days ago' : '3天前', '#1399BA', false, () => this.openSingleChat(10007, 'Frank Sun'))

          this.contactSectionTitle(this.english ? 'GROUPS' : '群组')
          this.contactRow('#', 'Work Team 工作群', this.english ? '8 members · Just now' : '8人 · 刚刚', '#07A5C7', false, () => this.openDemoGroupChat('Work Team 工作群'))
          this.contactRow('#', 'Family 家庭群', this.english ? '5 members · Today' : '5人 · 今天', '#06A46F', false, () => this.openDemoGroupChat('Family 家庭群'))
          this.contactRow('#', 'Project Alpha', this.english ? '12 members · Yesterday' : '12人 · 昨天', '#E58400', false, () => this.openDemoGroupChat('Project Alpha'))
        }.width('100%').padding({ bottom: 16 })
      }.layoutWeight(1).scrollBar(BarState.Off).backgroundColor(this.pageColor())
    }.width('100%').layoutWeight(1).backgroundColor(this.pageColor())
  }

  @Builder demoUsersPage() {
    Column() {
      Row() { Text('‹').fontSize(28).fontColor(this.textColor()).onClick(() => this.setScreen('contacts')); Text(this.english ? 'Registered demo users' : '已注册演示用户').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.textColor()).margin({ left: 12 }); Blank().layoutWeight(1) }.height(52).width('100%').padding({ left: 20, right: 20 }).backgroundColor(this.headerColor())
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.demoUserNames, (name: string, index: number) => {
            Button(`${name}`).type(ButtonType.Normal).width('100%').height(50).fontColor(this.textColor()).backgroundColor(this.panelColor()).borderRadius(14).onClick(() => { void this.addDemoFriend(index) })
          }, (name: string, index: number) => `${name}-${index}`)
        }.padding(20).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(this.pageColor())
  }

  @Builder profile() {
    Column() {
      this.pageHeader(this.english ? 'Me' : '我的')
      Scroll() {
        Column() {
          this.profileIdentity()
          this.profileShortcuts()
          Column() {
            this.profileThemeRow()
            this.profileLanguageRow()
            this.profileRow($r('app.media.PteIMUIProfileNotifications'), this.english ? 'Notifications' : '通知设置', () => {})
            this.profileRow($r('app.media.PteIMUIProfilePrivacy'), this.english ? 'Privacy & Security' : '隐私与安全', () => {})
            this.profileRow($r('app.media.PteIMUIProfileFeedback'), this.english ? 'Help & Feedback' : '帮助与反馈', () => {})
            this.profileRow($r('app.media.PteIMUIProfileSettings'), this.english ? 'Settings' : '设置', () => this.setScreen('settings'))
          }.width('100%').padding({ left: 20, right: 20, top: 14 }).backgroundColor(this.pageColor())
          Button() {
            Row({ space: 8 }) {
              Image($r('app.media.PteIMUIProfileLogout')).width(18).height(18)
              Text(this.english ? 'Log Out' : '退出登录').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#ED3340')
            }.justifyContent(FlexAlign.Center).width('100%')
          }.height(48).width('90%').margin({ top: 14, bottom: 24 }).borderRadius(16).backgroundColor(this.darkMode ? '#2A0F21' : '#F4DFE7').onClick(() => { this.client?.stop(); this.client = null; this.setScreen('login') })
        }.width('100%').backgroundColor(this.pageColor())
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').layoutWeight(1).backgroundColor(this.pageColor())
  }

  @Builder pageHeader(title: string) {
    Row({ space: 10 }) {
      Image($r('app.media.PteIMUIConversationLogo')).width(28).height(28)
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.textColor())
      Blank().layoutWeight(1)
    }.height(44).width('100%').padding({ left: 20, right: 20 }).backgroundColor(this.headerColor())
  }
  @Builder profileIdentity() {
    Row() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Text(this.english ? 'Me' : '我').width(64).height(64).fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White).textAlign(TextAlign.Center).backgroundColor('#4867E9').borderRadius(18)
        Circle({ width: 17, height: 17 }).fill('#09BF6B')
      }.width(64).height(64)
      Column({ space: 4 }) {
        Text(`User_${this.userId}`).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.textColor())
        Text(`ID: usr_${this.userId}5abc`).fontSize(11).fontColor(this.mutedColor())
      }.margin({ left: 16 }).alignItems(HorizontalAlign.Start)
      Blank().layoutWeight(1)
      Text('›').fontSize(26).fontColor(this.mutedColor())
    }.width('100%').height(112).padding({ left: 20, right: 22 }).linearGradient({ direction: GradientDirection.Right, colors: this.darkMode ? [['#12123A', 0.0], ['#0A1734', 1.0]] : [['#E1E4FF', 0.0], ['#D7EBFF', 1.0]] })
  }
  @Builder profileShortcuts() {
    Row() {
      this.profileShortcut($r('app.media.PteIMUIProfileFavorites'), '12', this.english ? 'Favorites' : '我的收藏')
      this.profileShortcut($r('app.media.PteIMUIProfileWallet'), '¥88', this.english ? 'Wallet' : '我的钱包')
      this.profileShortcut($r('app.media.PteIMUIProfileQRCode'), '', this.english ? 'QR Card' : '二维码名片')
    }.height(94).width('100%').backgroundColor(this.panelColor())
  }
  @Builder profileShortcut(icon: Resource, number: string, title: string) {
    Column({ space: 3 }) {
      Image(icon).width(22).height(22)
      if (number.length > 0) Text(number).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.textColor())
      else Blank().height(15)
      Text(title).fontSize(10).fontColor(this.mutedColor())
    }.layoutWeight(1).height(94).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
  }
  @Builder profileThemeRow() {
    Row({ space: 14 }) {
      Image($r('app.media.PteIMUIProfileTheme')).width(22).height(22)
      Text(this.darkMode ? (this.english ? 'Dark Mode' : '深色模式') : (this.english ? 'Light Mode' : '浅色模式')).fontSize(14).fontColor(this.textColor())
      Blank().layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.darkMode }).selectedColor('#8346F3').switchPointColor(Color.White).onChange((isOn: boolean) => this.applyTheme(isOn ? PteIMThemeMode.DARK : PteIMThemeMode.LIGHT))
    }.height(56).width('100%').padding({ left: 2, right: 10 }).border({ width: { bottom: 1 }, color: this.lineColor() })
  }
  @Builder profileLanguageRow() {
    Row({ space: 14 }) {
      Image($r('app.media.PteIMUIProfileLanguage')).width(22).height(22)
      Text(this.english ? 'Language' : '语言').fontSize(14).fontColor(this.textColor())
      Blank().layoutWeight(1)
      Text(this.languageName()).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#7D42EF').padding({ left: 12, right: 12, top: 6, bottom: 6 }).backgroundColor(this.darkMode ? '#281951' : '#E8E0FF').borderRadius(16)
    }.height(56).width('100%').padding({ left: 2, right: 0 }).border({ width: { bottom: 1 }, color: this.lineColor() }).onClick(() => this.setScreen('languageSettings'))
  }
  @Builder profileRow(icon: Resource, title: string, click: () => void) {
    Row({ space: 14 }) {
      Image(icon).width(22).height(22)
      Text(title).fontSize(14).fontColor(this.textColor())
      Blank().layoutWeight(1)
      Text('›').fontSize(24).fontColor(this.mutedColor())
    }.height(56).width('100%').padding({ left: 2, right: 4 }).border({ width: { bottom: 1 }, color: this.lineColor() }).onClick(click)
  }
  @Builder contactsHeader() {
    Row({ space: 8 }) {
      Image($r('app.media.PteIMUILogo')).width(28).height(28)
      Text(this.english ? 'Contacts' : '联系人').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.textColor()).layoutWeight(1)
      Image(this.darkMode ? $r('app.media.PteIMUIContactCreateDark') : $r('app.media.PteIMUIContactCreateLight')).width(44).height(44).padding(10).onClick(() => this.openDemoGroupChat())
    }.height(44).width('100%').padding({ left: 20, right: 20 }).backgroundColor(this.headerColor())
  }
  @Builder contactQuickAction(icon: Resource, title: string, click: () => void) {
    Row({ space: 10 }) {
      Image(icon).width(28).height(28)
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.textColor())
    }.height(48).layoutWeight(1).padding({ left: 12, right: 10 }).backgroundColor(this.darkMode ? '#1D1B4A' : '#EAE7FF').borderRadius(14).onClick(click)
  }
  @Builder contactSectionTitle(title: string) {
    Text(title).fontSize(10).fontWeight(FontWeight.Medium).letterSpacing(1.1).fontColor(this.mutedColor()).height(32).width('100%').padding({ left: 20, top: 12 })
  }
  @Builder contactRow(letter: string, name: string, subtitle: string, color: string, online: boolean, click: () => void) {
    Column() {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Text(letter).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White).textAlign(TextAlign.Center).width(40).height(40).backgroundColor(color).borderRadius(20)
          if (online) Circle({ width: 9, height: 9 }).fill('#12C96B')
        }.width(40).height(40)
        Column({ space: 3 }) {
          Text(name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.textColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(subtitle).fontSize(10).fontColor(this.mutedColor()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image(this.darkMode ? $r('app.media.PteIMUIContactArrowDark') : $r('app.media.PteIMUIContactArrowLight')).width(18).height(18)
      }.height(62).width('100%').padding({ left: 20, right: 18 }).onClick(click)
      Row() { Blank().width(20); Blank().layoutWeight(1).height(1).backgroundColor(this.lineColor()); Blank().width(20) }.height(1).width('100%')
    }.width('100%').backgroundColor(this.pageColor())
  }

  @Builder settingsPage() {
    Column() {
      this.backHeader(this.english ? 'Settings' : '设置', () => this.setScreen('profile'))
      Scroll() {
        Column({ space: 16 }) {
          Column() {
            this.settingsGroupTitle(this.english ? 'APPEARANCE · 外观' : '外观 · 外观')
            this.settingsThemeRow()
            this.settingsLanguageRow()
          }.width('100%').backgroundColor(this.panelColor()).borderRadius(16).border({ width: 1, color: this.lineColor() })
          Column() {
            this.settingsGroupTitle(this.english ? 'NOTIFICATIONS · 通知' : '通知 · 通知')
            this.settingsToggleRow($r('app.media.PteIMUISettingsNotifications'), this.english ? 'Notifications' : '通知设置', this.english ? 'Push' : '推送通知 Push', this.notificationsOn, (value: boolean) => this.notificationsOn = value)
            this.settingsToggleRow($r('app.media.PteIMUISettingsSound'), this.english ? 'Sound' : '声音', this.english ? 'Sound' : '消息提示音 Sound', this.soundOn, (value: boolean) => this.soundOn = value)
            this.settingsToggleRow($r('app.media.PteIMUISettingsReadReceipts'), this.english ? 'Read Receipts' : '已读回执', this.english ? 'Read Receipts' : '已读回执 Receipts', this.readReceiptsOn, (value: boolean) => this.readReceiptsOn = value)
          }.width('100%').backgroundColor(this.panelColor()).borderRadius(16).border({ width: 1, color: this.lineColor() })
          Column() {
            this.settingsGroupTitle(this.english ? 'PRIVACY & SECURITY · 隐私' : '隐私与安全 · 隐私')
            this.settingsLinkRow($r('app.media.PteIMUISettingsPrivacy'), this.english ? 'Privacy & Security' : '隐私与安全', this.english ? 'Privacy Settings' : '隐私设置')
            this.settingsLinkRow($r('app.media.PteIMUISettingsAccount'), this.english ? 'Account' : '账号管理', this.english ? 'Account Management' : '账号管理')
            this.settingsLinkRow($r('app.media.PteIMUIProfileFeedback'), this.english ? 'Help & Feedback' : '帮助与反馈', this.english ? 'Help Center' : '帮助中心')
            this.settingsLinkRow($r('app.media.PteIMUISettingsAbout'), this.english ? 'About' : '关于', 'v2.4.1')
          }.width('100%').backgroundColor(this.panelColor()).borderRadius(16).border({ width: 1, color: this.lineColor() })
          Column({ space: 4 }) {
            Text('PrivateChat v1.0.0').fontSize(11).fontColor(this.mutedColor())
            Text('© 2026 PrivateChat Inc.').fontSize(10).fontColor(this.mutedColor())
          }.width('100%').alignItems(HorizontalAlign.Center).margin({ top: 8, bottom: 22 })
        }.width('100%').padding({ left: 20, right: 20, top: 18 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(this.pageColor())
  }

  @Builder languageSettingsPage() {
    Column() {
      this.backHeader(this.english ? 'Language' : '语言', () => this.setScreen('profile'))
      Column({ space: 2 }) {
        this.languageOption(this.english ? 'Follow System' : '跟随系统', this.english ? 'Use device language' : '使用设备系统语言', this.languagePreference === 'system', () => this.applyLanguage(PteIMLanguage.SYSTEM))
        this.languageOption('简体中文', 'Simplified Chinese', this.languagePreference === 'zh_CN', () => this.applyLanguage(PteIMLanguage.ZH_CN))
        this.languageOption('English', 'English', this.languagePreference === 'en_US', () => this.applyLanguage(PteIMLanguage.EN_US))
      }.width('100%').margin({ left: 20, right: 20, top: 20 }).padding({ top: 6, bottom: 6 }).backgroundColor(this.panelColor()).borderRadius(16).border({ width: 1, color: this.lineColor() })
      Blank().layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(this.pageColor())
  }

  @Builder backHeader(title: string, back: () => void) {
    Row({ space: 12 }) {
      if (this.darkMode) Image($r('app.media.PteIMUIBack')).width(24).height(24).padding(4).onClick(back)
      else Text('‹').width(32).height(44).fontSize(32).fontColor(this.textColor()).textAlign(TextAlign.Center).onClick(back)
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.textColor())
      Blank().layoutWeight(1)
    }.height(44).width('100%').padding({ left: 16, right: 20 }).backgroundColor(this.headerColor()).border({ width: { bottom: 1 }, color: this.lineColor() })
  }
  @Builder settingsGroupTitle(title: string) { Text(title).height(40).fontSize(10).fontWeight(FontWeight.Bold).fontColor(this.mutedColor()).width('100%').padding({ left: 16, top: 14 }).border({ width: { bottom: 1 }, color: this.lineColor() }) }
  @Builder settingsThemeRow() {
    Row({ space: 14 }) {
      Image($r('app.media.PteIMUIProfileTheme')).width(22).height(22)
      Column({ space: 2 }) { Text(this.darkMode ? (this.english ? 'Dark Mode' : '深色模式') : (this.english ? 'Light Mode' : '浅色模式')).fontSize(14).fontColor(this.textColor()); Text(this.darkMode ? (this.english ? 'Dark' : '深色') : (this.english ? 'Light' : '浅色')).fontSize(11).fontColor(this.mutedColor()) }.alignItems(HorizontalAlign.Start)
      Blank().layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.darkMode }).selectedColor('#8346F3').switchPointColor(Color.White).onChange((isOn: boolean) => this.applyTheme(isOn ? PteIMThemeMode.DARK : PteIMThemeMode.LIGHT))
    }.height(68).width('100%').padding({ left: 16, right: 16 }).border({ width: { bottom: 1 }, color: this.lineColor() })
  }
  @Builder settingsLanguageRow() {
    Row({ space: 14 }) {
      Image($r('app.media.PteIMUIProfileLanguage')).width(22).height(22)
      Column({ space: 2 }) { Text(this.english ? 'Language' : '语言').fontSize(14).fontColor(this.textColor()); Text(this.languageName()).fontSize(11).fontColor(this.mutedColor()) }.alignItems(HorizontalAlign.Start)
      Blank().layoutWeight(1)
      Text(this.languageTag()).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#7D42EF').padding({ left: 12, right: 12, top: 7, bottom: 7 }).backgroundColor(this.darkMode ? '#281951' : '#E8E0FF').borderRadius(16)
    }.height(68).width('100%').padding({ left: 16, right: 16 }).onClick(() => this.setScreen('languageSettings'))
  }
  @Builder settingsToggleRow(icon: Resource, title: string, subtitle: string, value: boolean, change: (value: boolean) => void) {
    Row({ space: 14 }) {
      Image(icon).width(22).height(22)
      Column({ space: 2 }) { Text(title).fontSize(14).fontColor(this.textColor()); Text(subtitle).fontSize(11).fontColor(this.mutedColor()) }.alignItems(HorizontalAlign.Start)
      Blank().layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor('#8346F3').switchPointColor(Color.White).onChange(change)
    }.height(68).width('100%').padding({ left: 16, right: 16 }).border({ width: { bottom: 1 }, color: this.lineColor() })
  }
  @Builder settingsLinkRow(icon: Resource, title: string, subtitle: string) {
    Row({ space: 14 }) {
      Image(icon).width(22).height(22)
      Column({ space: 2 }) { Text(title).fontSize(14).fontColor(this.textColor()); Text(subtitle).fontSize(11).fontColor(this.mutedColor()) }.alignItems(HorizontalAlign.Start)
      Blank().layoutWeight(1)
      Text('›').fontSize(24).fontColor(this.mutedColor())
    }.height(68).width('100%').padding({ left: 16, right: 16 }).border({ width: { bottom: 1 }, color: this.lineColor() })
  }
  @Builder languageOption(title: string, subtitle: string, selected: boolean, choose: () => void) {
    Row({ space: 14 }) {
      Column({ space: 2 }) { Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.textColor()); Text(subtitle).fontSize(11).fontColor(this.mutedColor()) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (selected) Circle({ width: 12, height: 12 }).fill('#8346F3')
      else Circle({ width: 12, height: 12 }).fill(this.darkMode ? '#252241' : '#D9D8E8')
    }.height(66).width('100%').padding({ left: 16, right: 18 }).onClick(choose)
  }
  @Builder tabs() {
    Row() {
      this.tab(this.english ? 'Chats' : '会话', 'conversations', $r('app.media.PteIMUITabChatsSelected'))
      this.tab(this.english ? 'Contacts' : '联系人', 'contacts', $r('app.media.PteIMUITabContactsSelected'))
      this.tab(this.english ? 'Me' : '我的', 'profile', $r('app.media.PteIMUITabProfileSelected'))
    }.height(60).width('100%').backgroundColor(this.darkMode ? '#11102A' : '#FFFFFF').border({ width: { top: 1 }, color: this.darkMode ? '#29254D' : '#ECEBFA' })
  }
  @Builder tab(title: string, target: string, icon: Resource) {
    Column({ space: 2 }) {
      // Keep the artwork centered on the tab column. The unread badge has its own
      // top-right anchor so it cannot shift the icon or its label horizontally.
      Stack({ alignContent: Alignment.Center }) {
        Image(icon).width(22).height(22).colorFilter(drawing.ColorFilter.createBlendModeColorFilter(
          this.screen === target
            ? { alpha: 255, red: 138, green: 67, blue: 244 }
            : this.darkMode
              ? { alpha: 255, red: 154, green: 152, blue: 183 }
              : { alpha: 255, red: 117, green: 116, blue: 141 },
          drawing.BlendMode.SRC_IN,
        ))
        // Unread state belongs to Chats, not to its selected visual state.
        // Keep it near the tab's top edge, 2vp left of the previous anchor, without covering the icon.
        if (target === 'conversations') Text('7').fontSize(9).fontColor(Color.White).textAlign(TextAlign.Center).lineHeight(16).width(16).height(16).backgroundColor('#F02B38').borderRadius(8).align(Alignment.TopEnd).translate({ x: 18, y: -7 })
      // 54vp keeps the 22vp icon centred while reserving room for its unread badge.
      }.width(54).height(24)
      Text(title).fontSize(10).fontWeight(this.screen === target ? FontWeight.Medium : FontWeight.Regular).fontColor(this.screen === target ? '#8A43F4' : (this.darkMode ? '#9A98B7' : '#75748D'))
      if (this.screen === target) Blank().width(26).height(2).backgroundColor('#8A43F4').borderRadius(1)
      else Blank().height(2)
    }.layoutWeight(1).height(60).justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).onClick(() => this.setScreen(target))
  }
  @Builder formLabel(value: string) { Text(value).width('100%').textAlign(TextAlign.Start).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.darkMode ? '#F0EDFF' : '#17182B').margin({ bottom: 8 }) }
  @Builder formInput(placeholder: string, value: string, change: (value: string) => void, type: InputType) { TextInput({ placeholder: placeholder, text: value }).type(type).height(46).fontSize(15).fontColor(this.darkMode ? '#F0EDFF' : '#17182B').placeholderColor(this.darkMode ? '#A69FC7' : '#656982').backgroundColor(this.darkMode ? '#201E4C' : '#EDE9FF').borderRadius(18).padding({ left: 16, right: 16 }).onChange(change).width('100%').margin({ bottom: 10 }) }

  private demoChatMessages(): PteIMMessage[] {
    const base = Date.now() - 11 * 60 * 1000
    const incoming = (type: PteIMMessageType, text: string, offset: number, media: PteIMMedia | null = null, voice: PteIMVoice | null = null, location: PteIMLocation | null = null, business: PteIMBusinessContent | null = null): PteIMMessage => {
      const message = new PteIMMessage('preview-chat', type, text, '', '', media, voice, location, business, `preview-in-${offset}`, base + offset * 60 * 1000, PteIMSendState.SENT)
      message.senderId = 'alice'
      return message
    }
    const outgoing = (type: PteIMMessageType, text: string, offset: number, media: PteIMMedia | null = null, voice: PteIMVoice | null = null, location: PteIMLocation | null = null, business: PteIMBusinessContent | null = null, state: PteIMSendState = PteIMSendState.SENT): PteIMMessage => {
      const message = new PteIMMessage('preview-chat', type, text, '', '', media, voice, location, business, `preview-out-${offset}`, base + offset * 60 * 1000, state)
      message.senderId = 'demo-me'
      return message
    }
    return [
      incoming(PteIMMessageType.TEXT, this.english ? 'Hello! Are you there?' : '你好！在吗？Hey!\nAre you there?', 0),
      outgoing(PteIMMessageType.TEXT, this.english ? "Yes, what’s up?" : '在的，什么事？\nYes, what’s up?', 1),
      incoming(PteIMMessageType.LOCATION, '', 2, null, null, new PteIMLocation(31.2304, 121.4737, '上海市浦东新区张江科技园', 'Zhangjiang Hi-Tech Park, Pudong')),
      outgoing(PteIMMessageType.IMAGE, '', 3, new PteIMMedia('', '', '', 720, 960, 0, 0, 'Photo')),
      incoming(PteIMMessageType.VOICE, '', 4, null, new PteIMVoice('', 8000)),
      outgoing(PteIMMessageType.VOICE, '', 5, null, new PteIMVoice('', 15000)),
      incoming(PteIMMessageType.VIDEO, '', 6, new PteIMMedia('', '', '', 1280, 720, 32000, 0, 'video.mp4')),
      outgoing(PteIMMessageType.RED_PACKET, '', 7, null, null, null, new PteIMBusinessContent('red-1', 'Alice', this.english ? 'Best wishes!' : '恭喜发财，大吉大利')),
      incoming(PteIMMessageType.GIFT, '', 8, null, null, null, new PteIMBusinessContent('gift-1', this.english ? 'Starlight Box' : '星光礼盒', this.english ? 'Open your gift' : '打开礼物')),
      incoming(PteIMMessageType.ORDER, '', 9, null, null, null, new PteIMBusinessContent('order-1', 'iPhone 15 Pro 256GB 深空黑', '¥8,999')),
      outgoing(PteIMMessageType.FILE, '', 10, new PteIMMedia('', '', '', 0, 0, 0, 1024 * 320, '项目报价单.pdf', 'application/pdf'), null, null, null, PteIMSendState.PENDING),
    ]
  }

  private async connect(): Promise<void> {
    try {
      if (this.userId.length === 0 || this.userSig.length === 0) throw new Error('业务后端应返回 userId 与短期 UserSig')
      const bootstrap = AppStorage.get<PteIMSDKBootstrap>('pteDemoBootstrap')
      if (bootstrap === undefined) throw new Error('IMBaseConfig 初始化失败')
      this.client?.stop()
      this.client = await bootstrap.login(new PteIMLoginConfig(Number(this.sdkAppId), this.userId, this.userSig))
      this.setScreen('conversations')
    } catch (error) { this.showError(`登录错误：${error instanceof Error ? error.message : String(error)}`) }
  }

  private async loadCaptcha(): Promise<void> {
    try {
      const data = await this.demoRequest('/api/v1/demo/auth/captcha', new DemoAuthRequest()) as DemoCaptchaResponse
      if (data.captcha_id.length === 0 || data.image_data.length === 0) throw new Error('验证码响应不完整')
      this.captchaID = data.captcha_id
      this.captchaImage = data.image_data
    } catch (error) { this.showError(`验证码加载失败：${this.errorMessage(error)}`) }
  }

  private async authenticate(register: boolean): Promise<void> {
    try {
      if (this.mobile.length === 0 || this.password.length < 8 || this.captchaID.length === 0 || this.captchaCode.length === 0 || (register && this.nickname.length < 2)) throw new Error('请输入手机号、密码、图形验证码；注册还需昵称')
      const data = new DemoAuthRequest(); data.mobile = this.mobile; data.password = this.password; data.captcha_id = this.captchaID; data.captcha_code = this.captchaCode; data.device_id = 'harmony-demo'; data.platform = 'harmony'
      if (register) data.nickname = this.nickname
      const result = await this.demoRequest(register ? '/api/v1/demo/auth/register' : '/api/v1/demo/auth/login', data) as DemoAuthResponse
      this.sdkAppId = result.sdk_app_id; this.userId = result.user_id; this.userSig = result.user_sig
      await this.connect()
    } catch (error) { this.showError(`登录错误：${this.errorMessage(error)}`); this.captchaCode = ''; void this.loadCaptcha() }
  }

  private async openDemoUsers(): Promise<void> {
    try {
      const rows = await this.demoRequest('/api/v1/demo/users', new DemoAuthRequest(), true) as DemoUserResponse[]
      this.demoUserNames = rows.map((row: DemoUserResponse) => `${row.nickname} · ${row.mobile}`)
      this.demoUserIDs = rows.map((row: DemoUserResponse) => row.user_id)
      this.setScreen('demoUsers')
    } catch (error) { this.showError(`加载演示用户失败：${this.errorMessage(error)}`) }
  }

  private async addDemoFriend(index: number): Promise<void> {
    try { const data = new DemoFriendRequest(); data.target_user_id = this.demoUserIDs[index]; await this.demoRequest('/api/v1/demo/friends/add', data, true); this.showSuccess(this.english ? 'Friend added. You can now start a chat.' : '已添加好友，现在可以单聊。') }
    catch (error) { this.showError(`添加好友失败：${this.errorMessage(error)}`) }
  }

  private async demoRequest(path: string, body: Object, authenticated: boolean = false): Promise<Object> {
    const key = await PteIMResponseCrypto.createRequestKey()
    const primaryDomain = AppStorage.get<string>('pteDemoApiDomain') ?? 'https://api-im.ptelive.com'
    const domains = primaryDomain === 'http://10.0.2.2:11504'
      ? [primaryDomain]
      : [primaryDomain, 'http://10.0.2.2:11504']
    let lastError: Error = new Error('网络请求失败')
    for (let index = 0; index < domains.length; index++) {
      const request = http.createHttp()
      try {
        const header: Record<string, string> = { 'Content-Type': 'application/json', 'X-Pte-Response-Public-Key': key.publicKey }
        if (authenticated) { header['Authorization'] = `Bearer ${this.userSig}`; header['X-Pte-Sdk-AppId'] = this.sdkAppId; header['X-Pte-User-Id'] = this.userId }
        const options: DemoHttpRequestOptions = { method: http.RequestMethod.POST, header: header, extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000 }
        const response = await request.request(`${domains[index].replace(/\/$/, '')}${path}`, options)
        if (response.responseCode < 200 || response.responseCode >= 300) throw new Error(`服务响应 HTTP ${response.responseCode}`)
        const responseText = response.result.toString()
        if (responseText.length === 0) throw new Error('服务返回空响应')
        const root = await PteIMResponseCrypto.decryptResponse(JSON.parse(responseText) as Record<string, Object>, key)
        if (Number(root['code'] ?? 0) !== 1) throw new Error(String(root['msg'] ?? '请求失败'))
        const data = root['data']
        if (data === undefined) throw new Error('响应数据为空')
        return data
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(this.errorMessage(error))
      } finally { request.destroy() }
    }
    throw lastError
  }

  private errorMessage(error: Object): string {
    if (error instanceof Error) return error.message
    const value = error as Record<string, Object>
    const message = value['message'] ?? value['msg'] ?? value['code']
    if (message !== undefined) return String(message)
    try {
      const serialized = JSON.stringify(error)
      return serialized === '{}' ? '网络请求失败，请检查调试服务是否已启动' : serialized
    } catch (_ignored) {
      return '网络请求失败，请检查调试服务是否已启动'
    }
  }
  private showSuccess(message: string, position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM): void {
    this.noticeHandler.success(message, position)
  }
  private showError(message: string, position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM): void {
    this.noticeHandler.error(message, position)
  }
  private applyLanguage(language: PteIMLanguage): void {
    if (language === PteIMLanguage.SYSTEM) {
      this.languagePreference = 'system'
      this.english = this.isSystemEnglish()
    } else {
      this.languagePreference = language === PteIMLanguage.ZH_CN ? 'zh_CN' : 'en_US'
      this.english = language === PteIMLanguage.EN_US
    }
    this.client?.updateAppearance(undefined, this.selectedLanguage())
    this.saveAppearancePreferences()
  }

  private applyTheme(theme: PteIMThemeMode): void {
    this.themePreference = theme === PteIMThemeMode.DARK ? 'dark' : 'light'
    this.darkMode = theme === PteIMThemeMode.DARK
    this.client?.updateAppearance(theme, undefined)
    this.applySystemBarStyle()
    this.saveAppearancePreferences()
  }

  private async restoreAppearancePreferences(): Promise<void> {
    try {
      const store = await this.getAppearanceStore()
      if (store === null) return
      const savedTheme = await store.get('themePreference', 'auto') as string
      const savedLanguage = await store.get('languagePreference', 'system') as string
      this.themePreference = savedTheme === 'light' || savedTheme === 'dark' ? savedTheme : 'auto'
      this.languagePreference = savedLanguage === 'zh_CN' || savedLanguage === 'en_US' ? savedLanguage : 'system'
      this.refreshAutomaticAppearance()
      if (this.languagePreference === 'system') this.english = this.isSystemEnglish()
      else this.english = this.languagePreference === 'en_US'
      this.client?.updateAppearance(this.darkMode ? PteIMThemeMode.DARK : PteIMThemeMode.LIGHT, this.selectedLanguage())
      this.applySystemBarStyle()
    } catch (error) {
      console.error(`读取外观偏好失败：${String(error)}`)
    }
  }

  private refreshAutomaticAppearance(): void {
    if (this.themePreference === 'auto') this.darkMode = this.isAutomaticDarkMode()
    if (this.languagePreference === 'system') this.english = this.isSystemEnglish()
    this.applySystemBarStyle()
  }

  private isAutomaticDarkMode(): boolean {
    const hour = new Date().getHours()
    return hour < 7 || hour >= 19
  }

  private isSystemEnglish(): boolean {
    return !i18n.System.getSystemLanguage().toLowerCase().startsWith('zh')
  }

  private selectedLanguage(): PteIMLanguage {
    if (this.languagePreference === 'system') return PteIMLanguage.SYSTEM
    return this.languagePreference === 'zh_CN' ? PteIMLanguage.ZH_CN : PteIMLanguage.EN_US
  }

  private languageName(): string {
    if (this.languagePreference === 'system') return this.english ? 'Follow System' : '跟随系统'
    return this.languagePreference === 'zh_CN' ? '简体中文' : 'English'
  }

  private languageTag(): string {
    if (this.languagePreference === 'system') return this.english ? 'AUTO' : '自动'
    return this.languagePreference === 'zh_CN' ? '中文' : 'EN'
  }

  private pageColor(): string { return this.darkMode ? '#08081F' : '#F1F1FF' }
  private panelColor(): string { return this.darkMode ? '#12112E' : '#FFFFFF' }
  private headerColor(): string { return this.darkMode ? '#12112E' : '#FFFFFF' }
  /** Keep the system status bar flush with the visible 44vp top navigation bar. */
  private topNavigationColor(): string {
    if (this.showingStartup) return '#0B061B'
    if (this.screen === 'login' || this.screen === 'register') return this.darkMode ? '#0E111C' : '#F4F4FF'
    if (this.screen === 'chat' || this.screen === 'chatPreview') return this.darkMode ? '#141827' : '#FFFFFF'
    return this.headerColor()
  }
  private isRootScreen(): boolean { return this.screen === 'conversations' || this.screen === 'contacts' || this.screen === 'profile' }
  private setScreen(screen: string): void { this.screen = screen; this.applySystemBarStyle() }
  private applySystemBarStyle(): void {
    const stage = AppStorage.get<window.WindowStage>('pteDemoWindowStage')
    if (stage === undefined) return
    const topNavigationColor = this.topNavigationColor()
    const contentColor = this.showingStartup || this.darkMode ? '#FFFFFFFF' : '#FF25233F'
    stage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: topNavigationColor,
        statusBarContentColor: contentColor,
        // System-bar colours require an opaque alpha value; otherwise the gesture area reveals its default white backdrop.
        navigationBarColor: this.opaqueSystemBarColor(this.showingStartup ? '#0B061B' : ((this.screen === 'chat' || this.screen === 'chatPreview') ? topNavigationColor : this.pageColor())),
        navigationBarContentColor: contentColor,
      })
    }).catch((error: Error) => console.error(`更新 PteIMUIDemo 系统栏失败：${error.message}`))
  }
  private opaqueSystemBarColor(color: string): string { return color.length === 7 && color.startsWith('#') ? `#FF${color.substring(1)}` : color }
  private textColor(): string { return this.darkMode ? '#F0EFFF' : '#25233F' }
  private mutedColor(): string { return this.darkMode ? '#9A98B7' : '#76758F' }
  private lineColor(): string { return this.darkMode ? '#29254D' : '#E8E7F6' }

  private async getAppearanceStore(): Promise<preferences.Preferences | null> {
    try {
      if (this.appearanceStore !== null) return this.appearanceStore
      const context = AppStorage.get<common.UIAbilityContext>('pteDemoContext')
      if (context === undefined) return null
      this.appearanceStore = await preferences.getPreferences(context, 'pte_im_ui_demo_appearance')
      return this.appearanceStore
    } catch (error) {
      console.error(`打开外观偏好失败：${String(error)}`)
      return null
    }
  }

  private async saveAppearancePreferences(): Promise<void> {
    try {
      const store = await this.getAppearanceStore()
      if (store === null) return
      await store.put('themePreference', this.themePreference)
      await store.put('languagePreference', this.languagePreference)
      await store.flush()
    } catch (error) {
      console.error(`保存外观偏好失败：${String(error)}`)
    }
  }
  private async openSingleChat(peerUserId: number, title: string): Promise<void> {
    const client = this.client
    if (client === null) { this.openPreviewChat(`preview-user-${peerUserId}`, title, 'contacts'); return }
    try { const conversation = await client.openSingleConversation(peerUserId); this.chatReturnScreen = 'contacts'; this.conversationId = conversation.id.toString(); this.chatTitle = title; this.chatIsGroup = false; this.setScreen('chat') } catch { this.showError('无法打开会话：请检查好友关系和 IM 服务状态') }
  }
  private async openDemoGroupChat(title: string = 'Work Team 工作群'): Promise<void> {
    const client = this.client
    if (client === null) { this.openPreviewChat(`preview-group-${title}`, title, 'contacts'); return }
    try { const conversation = await client.createGroupConversation(title, [10002, 10003]); this.chatReturnScreen = 'contacts'; this.conversationId = conversation.id.toString(); this.chatTitle = title; this.chatIsGroup = true; this.setScreen('chat') } catch { this.showError('无法创建群组：请检查业务成员关系和 IM 服务状态') }
  }
  private openPreviewChat(conversationId: string, title: string, returnScreen: string): void {
    this.previewConversationId = conversationId
    this.previewChatTitle = title
    this.previewChatIsGroup = this.isGroupTitle(title)
    this.chatReturnScreen = returnScreen
    this.setScreen('chatPreview')
  }
  private isGroupTitle(title: string): boolean { return title.includes('Team') || title.includes('群') || title.includes('Project') || title.includes('Family') }
  private showAddFriendNotice(): void {
    try { this.getUIContext().getPromptAction().showToast({ message: this.english ? 'Add Friend is provided by the business layer' : '添加好友由业务层实现' }) }
    catch (error) { console.error(`显示添加好友提示失败：${String(error)}`) }
  }
  private handleAction(action: PteIMUIAction): void { const client = this.client; if (client === null) return; if (action === PteIMUIAction.LOCATION) client.sendLocation(this.conversationId, new PteIMLocation(31.2304, 121.4737, 'Shanghai', 'PteIMUIDemo')); else if (action === PteIMUIAction.GIFT) client.sendGift(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo gift')); else if (action === PteIMUIAction.RED_PACKET) client.sendRedPacket(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo red packet')); else if (action === PteIMUIAction.ORDER) client.sendOrder(this.conversationId, new PteIMBusinessContent(`demo-${Date.now()}`, 'Demo order')) }
}
