import { PteIMUIMediaPreviewHandler, PteIMUIMediaPreviewNavigationHandler } from './PteIMUIKit'
import { PteIMUIMediaPlayback } from './PteIMUIMediaPlayback'

/**
 * Independently embeddable image preview. Hosts can subclass the handler to save into an
 * album, or use this component directly in a custom router/page.
 */
@Component
export struct PteIMUIImagePreview {
  @Prop uri: string = ''
  @Prop handler: PteIMUIMediaPreviewHandler = new PteIMUIMediaPreviewHandler()
  @Prop dark: boolean = true
  @Prop navigationHandler: PteIMUIMediaPreviewNavigationHandler = new PteIMUIMediaPreviewNavigationHandler()

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text('').width('100%').height('100%').backgroundColor('#E6000000').onClick(() => this.navigationHandler.close())
      if (this.uri.length > 0) {
        Image(this.uri).width('92%').height('78%').objectFit(ImageFit.Contain)
          .gesture(LongPressGesture().onAction(() => this.handler.saveImage(this.uri)))
      }
      Button('×').width(44).height(44).fontSize(30).fontColor(Color.White).backgroundColor('#33000000').borderRadius(22)
        .position({ x: '86%', y: 24 }).onClick(() => this.navigationHandler.close())
    }.width('100%').height('100%')
  }
}

/**
 * Independently embeddable video preview. The native Video control provides pause/play
 * and its bottom progress track; the close control is always available in the upper right.
 */
@Component
export struct PteIMUIVideoPreview {
  @Prop uri: string = ''
  @Prop handler: PteIMUIMediaPreviewHandler = new PteIMUIMediaPreviewHandler()
  @Prop navigationHandler: PteIMUIMediaPreviewNavigationHandler = new PteIMUIMediaPreviewNavigationHandler()
  private controller: VideoController = new VideoController()

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text('').width('100%').height('100%').backgroundColor('#E6000000').onClick(() => this.navigationHandler.close())
      if (this.uri.length > 0) {
        Video({ src: this.uri, controller: this.controller }).width('100%').height('78%').objectFit(ImageFit.Contain).autoPlay(true).controls(true)
          .onStart(() => PteIMUIMediaPlayback.activate('video-preview', (): void => { this.controller.pause() }))
          .gesture(LongPressGesture().onAction(() => this.handler.saveVideo(this.uri)))
      }
      Button('×').width(44).height(44).fontSize(30).fontColor(Color.White).backgroundColor('#33000000').borderRadius(22)
        .position({ x: '86%', y: 24 }).onClick(() => { this.controller.pause(); PteIMUIMediaPlayback.release('video-preview'); this.navigationHandler.close() })
    }.width('100%').height('100%')
  }
}

/** Generic file preview gate. A tap delegates file opening; a long press delegates saving. */
@Component
export struct PteIMUIFilePreview {
  @Prop uri: string = ''
  @Prop fileName: string = ''
  @Prop handler: PteIMUIMediaPreviewHandler = new PteIMUIMediaPreviewHandler()
  @Prop navigationHandler: PteIMUIMediaPreviewNavigationHandler = new PteIMUIMediaPreviewNavigationHandler()

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text('').width('100%').height('100%').backgroundColor('#99000000').onClick(() => this.navigationHandler.close())
      Column({ space: 18 }) {
        Text(this.fileName.length > 0 ? this.fileName : 'File').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#20253A').maxLines(2).textAlign(TextAlign.Center)
        Button('Preview').width('100%').height(44).fontColor(Color.White).backgroundColor('#8D45F7').borderRadius(12)
          .onClick(() => this.handler.openFile(this.uri, this.fileName))
        Text('Long press to save').fontSize(12).fontColor('#707991')
          .gesture(LongPressGesture().onAction(() => this.handler.saveFile(this.uri, this.fileName)))
        Button('Close').width('100%').height(40).fontColor('#707991').backgroundColor(Color.Transparent).onClick(() => this.navigationHandler.close())
      }.width('78%').padding(24).backgroundColor(Color.White).borderRadius(20).alignItems(HorizontalAlign.Center)
    }.width('100%').height('100%')
  }
}
