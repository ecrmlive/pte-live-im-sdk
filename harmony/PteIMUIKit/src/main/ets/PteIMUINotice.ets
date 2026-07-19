/** Reusable success/error notice for UIKit host pages. */
export enum PteIMUINoticeKind {
  SUCCESS = 'success',
  ERROR = 'error',
  WARNING = 'warning',
}

/** Bottom notices keep the current page interactive; centered notices add a light modal veil. */
export enum PteIMUINoticePosition {
  BOTTOM = 'bottom',
  CENTER = 'center',
}

export class PteIMUINoticePayload {
  message: string
  kind: PteIMUINoticeKind
  position: PteIMUINoticePosition
  duration: number

  constructor(
    message: string,
    kind: PteIMUINoticeKind = PteIMUINoticeKind.SUCCESS,
    position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM,
    duration: number = 2600,
  ) {
    this.message = message
    this.kind = kind
    this.position = position
    this.duration = duration
  }
}

/**
 * Host-facing delegate. Keep one instance in a page and bind its callback to
 * PteIMUINotice state. This keeps transport/business errors out of UIKit views.
 */
export class PteIMUINoticeHandler {
  private callback: (notice: PteIMUINoticePayload) => void

  constructor(callback: (notice: PteIMUINoticePayload) => void = (_notice: PteIMUINoticePayload) => {}) {
    this.callback = callback
  }

  show(message: string, kind: PteIMUINoticeKind, position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM, duration: number = 2600): void {
    if (message.trim().length === 0) return
    this.callback(new PteIMUINoticePayload(message, kind, position, duration))
  }

  success(message: string, position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM, duration: number = 2600): void {
    this.show(message, PteIMUINoticeKind.SUCCESS, position, duration)
  }

  error(message: string, position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM, duration: number = 3200): void {
    this.show(message, PteIMUINoticeKind.ERROR, position, duration)
  }

  warning(message: string, position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM, duration: number = 3000): void {
    this.show(message, PteIMUINoticeKind.WARNING, position, duration)
  }
}

/** A typed close delegate because ArkUI V1 does not permit function-valued @Prop fields. */
export class PteIMUINoticeDismissHandler {
  private callback: () => void
  constructor(callback: () => void = () => {}) { this.callback = callback }
  dismiss(): void { this.callback() }
}

/** A self-dismissing ArkUI overlay. Place it as the last child of a page-level Stack. */
@Component
export struct PteIMUINotice {
  @Prop visible: boolean = false
  @Prop message: string = ''
  @Prop kind: PteIMUINoticeKind = PteIMUINoticeKind.SUCCESS
  @Prop noticePosition: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM
  @Prop dark: boolean = false
  @Prop duration: number = 2600
  @Prop @Watch('onRevisionChanged') revision: number = 0
  @Prop dismissHandler: PteIMUINoticeDismissHandler = new PteIMUINoticeDismissHandler()
  private dismissTimer: number = -1

  aboutToAppear(): void {
    this.scheduleDismiss()
  }

  aboutToDisappear(): void {
    this.cancelDismiss()
  }

  private onRevisionChanged(): void {
    this.scheduleDismiss()
  }

  private cancelDismiss(): void {
    if (this.dismissTimer !== -1) {
      clearTimeout(this.dismissTimer)
      this.dismissTimer = -1
    }
  }

  private scheduleDismiss(): void {
    this.cancelDismiss()
    if (!this.visible || this.message.length === 0 || this.duration <= 0) return
    this.dismissTimer = setTimeout(() => this.dismiss(), this.duration)
  }

  private dismiss(): void {
    this.cancelDismiss()
    this.dismissHandler.dismiss()
  }

  private panelColor(): string { return this.dark ? '#E922203B' : '#FDFDFFFF' }
  private noticeBorderColor(): string { return this.dark ? '#4D8B7DD4' : '#1A16142B' }
  private titleColor(): string { return this.dark ? '#F4F2FF' : '#201E33' }
  private detailColor(): string { return this.dark ? '#C9C4E8' : '#5E5A75' }
  private iconColor(): string {
    if (this.kind === PteIMUINoticeKind.SUCCESS) return '#20B878'
    if (this.kind === PteIMUINoticeKind.WARNING) return '#DA9418'
    return '#E5484D'
  }
  private iconText(): string { return this.kind === PteIMUINoticeKind.SUCCESS ? '✓' : '!' }
  private title(): string {
    if (this.kind === PteIMUINoticeKind.SUCCESS) return 'Success'
    if (this.kind === PteIMUINoticeKind.WARNING) return 'Warning'
    return 'Error'
  }

  @Builder noticeCard() {
    Row({ space: 10 }) {
      Text(this.iconText()).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Color.White).textAlign(TextAlign.Center)
        .width(24).height(24).borderRadius(12).backgroundColor(this.iconColor())
      Column({ space: 3 }) {
        Text(this.title()).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.titleColor())
        Text(this.message).fontSize(13).fontColor(this.detailColor()).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('×').type(ButtonType.Normal).width(28).height(28).fontSize(21).fontColor(this.detailColor()).backgroundColor(Color.Transparent).padding(0)
        .onClick(() => this.dismiss())
    }.width('100%').constraintSize({ maxWidth: 460 }).height(60).padding({ left: 14, top: 10, right: 8, bottom: 10 })
      .backgroundColor(this.panelColor()).border({ width: 1, color: this.noticeBorderColor(), radius: 16 })
      .shadow({ radius: 18, color: this.dark ? '#66000000' : '#2A1D1638', offsetX: 0, offsetY: 8 })
  }

  build() {
    Stack({ alignContent: this.noticePosition === PteIMUINoticePosition.CENTER ? Alignment.Center : Alignment.Bottom }) {
      if (this.noticePosition === PteIMUINoticePosition.CENTER) {
        Column() {}.width('100%').height('100%').backgroundColor('#33000000').onClick(() => this.dismiss())
      }
      if (this.visible && this.message.length > 0) {
        this.noticeCard()
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, bottom: this.noticePosition === PteIMUINoticePosition.BOTTOM ? 32 : 0 })
  }
}
