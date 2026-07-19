package com.ptelive.im.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.ContentValues
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.VideoView
import com.ptelive.im.PteIMMessage
import java.net.URL
import java.util.concurrent.Executors

/**
 * UIKit-owned media preview. It has no third-party dependency: images use an
 * [ImageView] and videos use Android's native [VideoView]/[MediaController].
 */
open class PteIMUIMediaPreviewActivity : Activity() {
  enum class Kind { IMAGE, VIDEO }

  companion object {
    const val EXTRA_URI = "pte.im.ui.preview.uri"
    const val EXTRA_KIND = "pte.im.ui.preview.kind"
    const val EXTRA_TITLE = "pte.im.ui.preview.title"

    fun open(
      context: Context,
      message: PteIMMessage,
      kind: Kind,
      activityClass: Class<out Activity> = PteIMUIMediaPreviewActivity::class.java,
    ) {
      val uri = message.media?.url ?: message.media?.thumbnailUrl.orEmpty()
      val intent = Intent(context, activityClass)
        .putExtra(EXTRA_URI, uri)
        .putExtra(EXTRA_KIND, kind.name)
        .putExtra(EXTRA_TITLE, message.media?.fileName.orEmpty())
      if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
    }
  }

  private val executor = Executors.newSingleThreadExecutor()
  private val mainHandler = Handler(Looper.getMainLooper())
  private var progressTicker: Runnable? = null
  private var videoPlaybackKey: String? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    window.statusBarColor = Color.rgb(8, 8, 31)
    window.navigationBarColor = Color.rgb(8, 8, 31)

    val kind = runCatching { Kind.valueOf(intent.getStringExtra(EXTRA_KIND).orEmpty()) }.getOrDefault(Kind.IMAGE)
    val uriText = intent.getStringExtra(EXTRA_URI).orEmpty()
    val root = FrameLayout(this).apply { setBackgroundColor(Color.rgb(8, 8, 31)) }
    setContentView(root)
    when (kind) {
      Kind.IMAGE -> addImage(root, uriText)
      Kind.VIDEO -> addVideo(root, uriText)
    }
    root.addView(ImageButton(this).apply {
      setImageResource(R.drawable.pte_im_ui_chat_back)
      contentDescription = "Back"
      setBackgroundColor(Color.TRANSPARENT)
      scaleType = ImageView.ScaleType.FIT_XY
      setPadding(0, 0, 0, 0)
      setOnClickListener { finish() }
    }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply {
      leftMargin = dp(12)
      topMargin = dp(8)
    })
    root.addView(ImageButton(this).apply {
      setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
      contentDescription = "Close"
      setBackgroundColor(Color.TRANSPARENT)
      setColorFilter(Color.WHITE)
      setPadding(dp(8), dp(8), dp(8), dp(8))
      setOnClickListener { finish() }
    }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END).apply {
      rightMargin = dp(12)
      topMargin = dp(8)
    })
  }

  override fun onDestroy() {
    videoPlaybackKey?.let(PteIMUIMediaPlayback::release)
    progressTicker?.let(mainHandler::removeCallbacks)
    progressTicker = null
    executor.shutdownNow()
    super.onDestroy()
  }

  /** Override to install a zoomable or annotated image canvas. */
  protected open fun addImage(root: FrameLayout, uriText: String) {
    val image = ImageView(this).apply {
      scaleType = ImageView.ScaleType.FIT_CENTER
      setImageResource(R.drawable.pte_im_ui_chat_message_image)
      setOnClickListener { finish() }
      setOnLongClickListener { saveToGallery(uriText); true }
    }
    root.addView(image, FrameLayout.LayoutParams(-1, -1))
    if (uriText.isBlank()) return
    executor.execute {
      runCatching {
        val uri = Uri.parse(uriText)
        val stream = when (uri.scheme) {
          "content", "file" -> contentResolver.openInputStream(uri)
          else -> URL(uriText).openConnection().getInputStream()
        } ?: error("Cannot open image")
        stream.use(BitmapFactory::decodeStream)
      }.onSuccess { bitmap ->
        if (bitmap != null && !isFinishing) runOnUiThread { image.setImageBitmap(bitmap) }
      }
    }
  }

  /** Override to replace the native video player while retaining preview routing. */
  protected open fun addVideo(root: FrameLayout, uriText: String) {
    if (uriText.isBlank()) {
      root.addView(ImageView(this).apply {
        setImageResource(R.drawable.pte_im_ui_chat_message_video_play)
        scaleType = ImageView.ScaleType.FIT_CENTER
      }, FrameLayout.LayoutParams(dp(46), dp(46), Gravity.CENTER))
      root.addView(TextView(this).apply {
        text = "Video is unavailable"
        textSize = 14f
        setTextColor(Color.WHITE)
      }, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL).apply { topMargin = dp(88) })
      return
    }
    val video = VideoView(this).apply {
      val uri = Uri.parse(uriText)
      setVideoURI(uri)
      setOnPreparedListener { player ->
        player.isLooping = false
        videoPlaybackKey = "video:${uriText}"
        PteIMUIMediaPlayback.activateVideo(videoPlaybackKey!!) { pause() }
        start()
      }
    }
    root.addView(video, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
    val playPause = ImageButton(this).apply {
      setImageResource(android.R.drawable.ic_media_pause)
      setBackgroundColor(Color.TRANSPARENT)
      setColorFilter(Color.WHITE)
      setOnClickListener {
        if (video.isPlaying) {
          video.pause(); setImageResource(android.R.drawable.ic_media_play)
        } else {
          videoPlaybackKey = "video:${uriText}"
          PteIMUIMediaPlayback.activateVideo(videoPlaybackKey!!) { video.pause() }
          video.start(); setImageResource(android.R.drawable.ic_media_pause)
        }
      }
    }
    root.addView(playPause, FrameLayout.LayoutParams(dp(46), dp(46), Gravity.CENTER))
    val progress = SeekBar(this).apply {
      max = 1
      setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
        override fun onProgressChanged(seekBar: SeekBar?, value: Int, fromUser: Boolean) { if (fromUser) video.seekTo(value) }
        override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
        override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
      })
    }
    root.addView(progress, FrameLayout.LayoutParams(-1, dp(36), Gravity.BOTTOM).apply { leftMargin = dp(16); rightMargin = dp(16); bottomMargin = dp(12) })
    val tick = object : Runnable {
      override fun run() {
        if (!isFinishing) {
          val duration = video.duration.coerceAtLeast(1)
          progress.max = duration
          if (!progress.isPressed) progress.progress = video.currentPosition.coerceAtLeast(0)
          playPause.setImageResource(if (video.isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)
          mainHandler.postDelayed(this, 250)
        }
      }
    }
    progressTicker = tick
    mainHandler.post(tick)
  }

  /** Saves an image preview into the user's Photos collection after a long press. */
  protected open fun saveToGallery(uriText: String) {
    if (uriText.isBlank()) return
    executor.execute {
      runCatching {
        val target = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
          put(MediaStore.Images.Media.DISPLAY_NAME, "PteIM-${System.currentTimeMillis()}.jpg")
          put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        }) ?: error("Cannot create image destination")
        sourceStream(uriText).use { input -> contentResolver.openOutputStream(target)?.use { output -> input.copyTo(output) } ?: error("Cannot write image") }
      }.onSuccess { runOnUiThread { PteIMUINotice.success(this, "已保存到相册") } }
        .onFailure { error -> runOnUiThread { PteIMUINotice.error(this, error.message ?: "保存失败") } }
    }
  }

  protected fun sourceStream(uriText: String) = when (Uri.parse(uriText).scheme) {
    "content", "file" -> contentResolver.openInputStream(Uri.parse(uriText)) ?: error("Cannot open media")
    else -> URL(uriText).openConnection().getInputStream()
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
