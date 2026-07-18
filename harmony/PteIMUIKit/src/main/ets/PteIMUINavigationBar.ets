import { PteIMLanguage, PteIMThemeMode } from '@ptelive/pte-im-sdk'

/** Callback holder for the V1 ArkUI component API. */
export class PteIMUINavigationHandler {
  private readonly languageSelected: (language: PteIMLanguage) => void
  private readonly themeSelected: (theme: PteIMThemeMode) => void
  constructor(languageSelected: (language: PteIMLanguage) => void = () => {}, themeSelected: (theme: PteIMThemeMode) => void = () => {}) { this.languageSelected = languageSelected; this.themeSelected = themeSelected }
  selectLanguage(language: PteIMLanguage): void { this.languageSelected(language) }
  selectTheme(theme: PteIMThemeMode): void { this.themeSelected(theme) }
}

/** Optional back action for pages that should not expose the language picker. */
export class PteIMUINavigationBackHandler {
  private readonly callback: () => void
  constructor(callback: () => void = () => {}) { this.callback = callback }
  back(): void { this.callback() }
}

/** Shared ArkUI navigation bar: current language, language picker and supplied light/dark artwork. */
@Component
export struct PteIMUINavigationBar {
  @Prop title: string = ''
  @Prop language: PteIMLanguage = PteIMLanguage.EN_US
  @Prop dark: boolean = false
  @Prop showBack: boolean = false
  @Prop handler: PteIMUINavigationHandler = new PteIMUINavigationHandler()
  @Prop backHandler: PteIMUINavigationBackHandler = new PteIMUINavigationBackHandler()
  @State menuOpen: boolean = false

  build() {
    Column() {
      Row() {
        if (this.showBack) {
          Button() {
            Image(this.dark ? $r('app.media.PteIMUIChatNavBackDark') : $r('app.media.PteIMUIChatNavBackLight')).width(44).height(44).objectFit(ImageFit.Fill)
          }.type(ButtonType.Normal).width(44).height(44).padding(0).backgroundColor(Color.Transparent).onClick(() => this.backHandler.back())
        } else {
          Text(this.languageTitle()).fontSize(14).fontColor(this.dark ? '#CCD3F2' : '#656982').width(122).height(34).textAlign(TextAlign.Center).padding({ left: 12, right: 12 }).backgroundColor(this.dark ? '#25224D' : Color.Transparent).borderRadius(18).onClick(() => this.menuOpen = !this.menuOpen)
        }
        Text(this.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#EFF2FF' : '#171C2E').textAlign(TextAlign.Center).layoutWeight(1)
        Image(this.dark ? $r('app.media.PteIMUINavigationThemeDark') : $r('app.media.PteIMUINavigationThemeLight')).width(40).height(40).padding(8).backgroundColor(this.dark ? '#222044' : Color.Transparent).borderRadius(20).onClick(() => this.handler.selectTheme(this.dark ? PteIMThemeMode.LIGHT : PteIMThemeMode.DARK))
      }.width('100%').height(44).padding({ left: 15, right: 15 }).backgroundColor(this.dark ? '#0E111C' : '#F4F4FF')
      if (!this.showBack && this.menuOpen) Column() {
        this.languageItem(PteIMLanguage.SYSTEM, '跟随系统')
        this.languageItem(PteIMLanguage.ZH_CN, '简体中文')
        this.languageItem(PteIMLanguage.EN_US, 'English')
      }.width(184).padding(6).alignItems(HorizontalAlign.Start).backgroundColor(this.dark ? '#181735' : Color.White).border({ width: 1, color: this.dark ? '#3C3668' : '#E7E2FA', radius: 18 }).margin({ left: 15, top: 8 })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder private languageItem(language: PteIMLanguage, title: string) {
    Row() {
      Text(title).fontSize(15).fontColor(this.dark ? '#EFEDFF' : '#25233F').layoutWeight(1)
      if (this.language === language) Circle({ width: 10, height: 10 }).fill('#8B53F4')
    }.width('100%').height(44).padding({ left: 14, right: 12 }).alignItems(VerticalAlign.Center).backgroundColor(this.language === language ? (this.dark ? '#2A2654' : '#F2EDFF') : Color.Transparent).borderRadius(13).onClick(() => this.select(language))
  }

  private select(language: PteIMLanguage): void { this.menuOpen = false; this.handler.selectLanguage(language) }
  private languageTitle(): string { return this.language === PteIMLanguage.ZH_CN ? '简体中文' : this.language === PteIMLanguage.SYSTEM ? '跟随系统' : 'English' }
}
