import media from '@ohos.multimedia.media'

/**
 * UIKit's process-wide media ownership gate. Native audio/video integrations
 * register their stop callback here, so a new item can never overlap an older
 * voice or video in another chat page.
 */
let activeKey: string = ''
let stopCurrent: (() => void) | null = null
let voicePlayer: media.AVPlayer | null = null

export class PteIMUIMediaPlayback {

  static playVoice(key: string, source: string): void {
    if (source.length === 0) return
    if (activeKey === key && voicePlayer !== null) { PteIMUIMediaPlayback.stop(); return }
    PteIMUIMediaPlayback.stop()
    activeKey = key
    media.createAVPlayer().then((player: media.AVPlayer): void => {
      if (activeKey !== key) { player.release(); return }
      voicePlayer = player
      player.url = source
      player.prepare().then((): void => {
        if (activeKey === key && voicePlayer === player) player.play()
      }).catch((): void => { PteIMUIMediaPlayback.release(key) })
    }).catch((): void => { PteIMUIMediaPlayback.release(key) })
  }

  static activate(key: string, stop: () => void): void {
    if (activeKey !== key) PteIMUIMediaPlayback.stop()
    activeKey = key
    stopCurrent = stop
  }

  static release(key: string): void {
    if (activeKey !== key) return
    const player = voicePlayer
    PteIMUIMediaPlayback.clear()
    if (player !== null) player.release()
  }

  static stop(): void {
    const callback = stopCurrent
    const player = voicePlayer
    PteIMUIMediaPlayback.clear()
    if (player !== null) player.release()
    if (callback !== null) callback()
  }

  private static clear(): void {
    activeKey = ''
    stopCurrent = null
    voicePlayer = null
  }
}
