package com.ptelive.im.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer

/**
 * UIKit-wide exclusive media playback coordinator.  Message cells and preview
 * pages route through it so a newly started voice/video always stops the old
 * one, even when they were created by different conversations.
 */
object PteIMUIMediaPlayback {
  private var activeKey: String? = null
  private var voicePlayer: MediaPlayer? = null
  private var stopVideo: (() -> Unit)? = null

  @Synchronized
  fun playVoice(context: Context, key: String, source: String) {
    if (source.isBlank()) return
    if (activeKey == key && voicePlayer != null) { stop(); return }
    stop()
    val player = MediaPlayer()
    runCatching {
      player.setAudioAttributes(AudioAttributes.Builder().setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).setUsage(AudioAttributes.USAGE_MEDIA).build())
      player.setDataSource(source)
      player.setOnPreparedListener { it.start() }
      player.setOnCompletionListener { release(key) }
      player.setOnErrorListener { _, _, _ -> release(key); true }
      activeKey = key
      voicePlayer = player
      player.prepareAsync()
    }.onFailure { player.release(); clear() }
  }

  @Synchronized
  fun activateVideo(key: String, stop: () -> Unit) {
    if (activeKey != key) stop()
    activeKey = key
    stopVideo = stop
  }

  @Synchronized
  fun release(key: String) {
    if (activeKey != key) return
    voicePlayer?.release()
    clear()
  }

  @Synchronized
  fun stop() {
    voicePlayer?.run { stop(); release() }
    stopVideo?.invoke()
    clear()
  }

  private fun clear() { voicePlayer = null; stopVideo = null; activeKey = null }
}
