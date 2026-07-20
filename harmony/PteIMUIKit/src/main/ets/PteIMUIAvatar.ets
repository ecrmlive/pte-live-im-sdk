/** Reusable IM avatar. Default is a circle; set cornerRadius in vp to override it. */
@Component
export struct PteIMUIAvatar {
  @Prop url: string = ''
  @Prop label: string = '?'
  @Prop avatarSize: number = 44
  @Prop cornerRadius: number = -1
  @Prop fillColor: string = '#8757F6'
  @Prop online: boolean = false

  private radius(): number { return Math.max(0, Math.min(this.cornerRadius >= 0 ? this.cornerRadius : this.avatarSize / 2, this.avatarSize / 2)) }
  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.url.length > 0) Image(this.url).width(this.avatarSize).height(this.avatarSize).objectFit(ImageFit.Cover).borderRadius(this.radius()).clip(true)
      else Text(this.label).width(this.avatarSize).height(this.avatarSize).textAlign(TextAlign.Center).fontSize(this.avatarSize * 0.34).fontWeight(FontWeight.Medium).fontColor(Color.White).backgroundColor(this.fillColor).borderRadius(this.radius())
      if (this.online) Circle({ width: 10, height: 10 }).fill('#12C96B')
    }.width(this.avatarSize).height(this.avatarSize)
  }
}
