import { PteIMContact, PteIMContactPage, PteIMGroupPage, PteIMLanguage, PteIMSDK, PteIMThemeMode } from '@ptelive/pte-im-sdk'
import { PteIMUIAvatarHandler, PteIMUIContactHandler, PteIMUIContactListMode, PteIMUILoadErrorHandler } from './PteIMUIKit'
import { PteIMUITheme, PteIMUIThemePalette } from './PteIMUITheme'

/** A normalised display row lets the host use one custom route for people and groups. */
export class PteIMUIContactPresentation {
  identifier: string = ''
  title: string = ''
  subtitle: string = ''
  avatarText: string = ''
  isGroup: boolean = false
}

/** Override transform() in the host to rewrite SDK contacts without owning pagination. */
export class PteIMUIContactPresentationTransformer {
  transform(value: PteIMUIContactPresentation): PteIMUIContactPresentation { return value }
}

/**
 SDK-driven cursor list for friends, follows and groups. ArkUI components are
 composed rather than inherited, so hosts customise selection through handlers
 and can supply a separate component when they need a bespoke row layout.
 */
@Component
export struct PteIMUIContactList {
  @Prop client: PteIMSDK
  @Prop mode: PteIMUIContactListMode = PteIMUIContactListMode.FRIENDS
  @Prop contactHandler: PteIMUIContactHandler = new PteIMUIContactHandler()
  @Prop avatarHandler: PteIMUIAvatarHandler = new PteIMUIAvatarHandler()
  @Prop errorHandler: PteIMUILoadErrorHandler = new PteIMUILoadErrorHandler()
  @Prop presentationTransformer: PteIMUIContactPresentationTransformer = new PteIMUIContactPresentationTransformer()
  @Prop theme: PteIMUITheme = new PteIMUITheme()
  @StorageProp('colorMode') systemColorMode: string = 'light'
  @State contacts: PteIMUIContactPresentation[] = []
  @State hasMore: boolean = false
  @State loading: boolean = false
  private cursor: string = ''

  aboutToAppear(): void { this.refresh() }
  build() {
    Column() {
      this.navigationBar()
      Row({ space: 24 }) {
        Row({ space: 8 }) { Text('＋').width(30).height(30).textAlign(TextAlign.Center).fontColor(this.palette().outgoingEnd).fontSize(20).backgroundColor(this.palette().panel).borderRadius(15); Text(this.client.currentAppearance().language.toString() === 'en-US' ? 'Add Friend' : '添加好友').fontSize(14).fontColor(this.palette().text) }.layoutWeight(1)
        Row({ space: 8 }) { Text('◉').width(30).height(30).textAlign(TextAlign.Center).fontColor(this.palette().outgoingEnd).fontSize(16).backgroundColor(this.palette().panel).borderRadius(15); Text(this.client.currentAppearance().language.toString() === 'en-US' ? 'New Group' : '新建群组').fontSize(14).fontColor(this.palette().text) }.layoutWeight(1)
      }.padding({ left: 20, right: 20, top: 18, bottom: 14 }).backgroundColor(this.palette().background)
      Text(this.mode === PteIMUIContactListMode.GROUPS ? (this.client.currentAppearance().language.toString() === 'en-US' ? 'GROUPS' : '群组') : (this.client.currentAppearance().language.toString() === 'en-US' ? 'PERSONAL' : '联系人')).fontSize(10).fontWeight(FontWeight.Medium).fontColor(this.palette().muted).letterSpacing(1.3).width('100%').padding({ left: 20, top: 4, bottom: 4 })
    List() {
      ForEach(this.contacts, (item: PteIMUIContactPresentation) => {
        ListItem() {
          Row({ space: 12 }) {
            Text(item.avatarText).width(42).height(42).textAlign(TextAlign.Center).fontColor(Color.White).fontSize(15).linearGradient({ angle: 90, colors: [[this.palette().outgoingStart, 0.0], [this.palette().outgoingEnd, 1.0]] }).borderRadius(21).onClick(() => this.avatarHandler.tap(item.identifier, item.isGroup))
            Column({ space: 4 }) {
              Text(item.title).fontSize(16).fontColor(this.palette().text)
              if (item.subtitle.length > 0) Text(item.subtitle).fontSize(13).fontColor(this.palette().muted)
            }.layoutWeight(1).onClick(() => this.select(item))
          }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 12 }).backgroundColor(this.palette().background)
        }.onAppear(() => { if (item.identifier === this.lastIdentifier()) this.loadNextPage() })
      }, (item: PteIMUIContactPresentation) => `${item.isGroup}:${item.identifier}`)
    }.layoutWeight(1).width('100%').backgroundColor(this.palette().background)
    }.width('100%').height('100%').backgroundColor(this.palette().background)
  }

  /** Restart from the first SDK cursor. In CUSTOM mode host data is left intact. */
  refresh(): void { this.cursor = ''; this.hasMore = false; if (this.mode !== PteIMUIContactListMode.CUSTOM) this.loadNextPage(true) }
  /** Public pagination hook for hosts with a custom scroll container. */
  async loadNextPage(replacing: boolean = false): Promise<void> {
    if (this.mode === PteIMUIContactListMode.CUSTOM || this.loading || (!replacing && !this.hasMore && this.contacts.length > 0)) return
    this.loading = true
    const cursor = replacing ? '' : this.cursor
    try {
      if (this.mode === PteIMUIContactListMode.GROUPS) {
        const page = await this.client.fetchGroups(cursor, 50)
        this.apply(this.groupPresentations(page), page.nextCursor, page.hasMore, replacing)
      } else {
        const page = this.mode === PteIMUIContactListMode.FOLLOWS ? await this.client.fetchFollows(cursor, 50) : await this.client.fetchFriends(cursor, 50)
        this.apply(this.contactPresentations(page), page.nextCursor, page.hasMore, replacing)
      }
    } catch (error) { this.loading = false; this.errorHandler.receive('无法加载联系人或群组') }
  }
  /** CUSTOM mode can replace rows without an SDK request. */
  setCustomContacts(values: PteIMUIContactPresentation[]): void {
    if (this.mode !== PteIMUIContactListMode.CUSTOM) { this.errorHandler.receive('自定义联系人仅可在 CUSTOM 模式使用'); return }
    this.contacts = values; this.cursor = ''; this.hasMore = false
  }
  private async select(item: PteIMUIContactPresentation): Promise<void> {
    try {
      if (item.isGroup) { this.contactHandler.select(item.identifier, item.title); return }
      const conversation = await this.client.openSingleConversation(Number(item.identifier))
      this.contactHandler.select(conversation.id.toString(), item.title)
    } catch (error) { this.errorHandler.receive('无法打开会话') }
  }
  private contactPresentations(page: PteIMContactPage): PteIMUIContactPresentation[] {
    return page.list.map((contact: PteIMContact): PteIMUIContactPresentation => {
      const value = new PteIMUIContactPresentation()
      value.identifier = contact.userId
      value.title = contact.remark.length > 0 ? contact.remark : (contact.nickname.length > 0 ? contact.nickname : contact.userId)
      value.subtitle = contact.remark.length > 0 ? contact.nickname : ''
      value.avatarText = value.title.substring(0, 1)
      return this.presentationTransformer.transform(value)
    })
  }
  private groupPresentations(page: PteIMGroupPage): PteIMUIContactPresentation[] {
    return page.list.map((group): PteIMUIContactPresentation => {
      const value = new PteIMUIContactPresentation()
      value.identifier = group.id.toString(); value.title = group.title.length > 0 ? group.title : value.identifier; value.avatarText = value.title.substring(0, 1); value.isGroup = true
      return this.presentationTransformer.transform(value)
    })
  }
  private apply(values: PteIMUIContactPresentation[], nextCursor: string, hasMore: boolean, replacing: boolean): void {
    const combined = replacing ? values : this.contacts.concat(values)
    const out: PteIMUIContactPresentation[] = []
    combined.forEach((value: PteIMUIContactPresentation) => { if (!out.some((existing: PteIMUIContactPresentation) => existing.identifier === value.identifier && existing.isGroup === value.isGroup)) out.push(value) })
    this.contacts = out; this.cursor = nextCursor; this.hasMore = hasMore; this.loading = false
  }
  private lastIdentifier(): string { return this.contacts.length > 0 ? this.contacts[this.contacts.length - 1].identifier : '' }
  @Builder navigationBar() {
    Row() {
      Row({ space: 10 }) { Text('◉').width(34).height(34).textAlign(TextAlign.Center).fontColor(Color.White).fontSize(16).linearGradient({ angle: 90, colors: [[this.palette().outgoingStart, 0.0], [this.palette().outgoingEnd, 1.0]] }).borderRadius(17); Text(this.client.currentAppearance().language.toString() === 'en-US' ? 'Contacts' : '联系人').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette().text) }.layoutWeight(1)
      Row({ space: 14 }) { Text('◐').fontSize(18).fontColor(this.palette().icon).onClick(() => this.toggleAppearance()); Text('◎').fontSize(18).fontColor(this.palette().icon).onClick(() => this.toggleLanguage()); Text('＋').fontSize(22).fontColor(this.palette().icon) }
    }.height(56).padding({ left: 18, right: 18 }).backgroundColor(this.palette().surface)
  }
  private toggleAppearance(): void { const appearance = this.client.currentAppearance(); this.client.updateAppearance(appearance.themeMode === PteIMThemeMode.DARK ? PteIMThemeMode.LIGHT : PteIMThemeMode.DARK, appearance.language) }
  private toggleLanguage(): void { const appearance = this.client.currentAppearance(); this.client.updateAppearance(appearance.themeMode, appearance.language === PteIMLanguage.EN_US ? PteIMLanguage.ZH_CN : PteIMLanguage.EN_US) }
  private palette(): PteIMUIThemePalette { return PteIMUITheme.resolve(this.client, this.theme, this.systemColorMode === 'dark') }
}
