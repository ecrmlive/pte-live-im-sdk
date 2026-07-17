package com.ptelive.im.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.MediaController
import android.widget.TextView
import android.widget.VideoView
import com.ptelive.im.PteIMMessage
import java.net.URL
import java.util.concurrent.Executors

/**
 * UIKit-owned media preview. It has no third-party dependency: images use an
 * [ImageView] and videos use Android's native [VideoView]/[MediaController].
 */
class PteIMUIMediaPreviewActivity : Activity() {
  enum class Kind { IMAGE, VIDEO }

  companion object {
    private const val EXTRA_URI = "pte.im.ui.preview.uri"
    private const val EXTRA_KIND = "pte.im.ui.preview.kind"
    private const val EXTRA_TITLE = "pte.im.ui.preview.title"

    fun open(context: Context, message: PteIMMessage, kind: Kind) {
      val uri = message.media?.url ?: message.media?.thumbnailUrl.orEmpty()
      val intent = Intent(context, PteIMUIMediaPreviewActivity::class.java)
        .putExtra(EXTRA_URI, uri)
        .putExtra(EXTRA_KIND, kind.name)
        .putExtra(EXTRA_TITLE, message.media?.fileName.orEmpty())
      if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
    }
  }

  private val executor = Executors.newSingleThreadExecutor()

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
  }

  override fun onDestroy() {
    executor.shutdownNow()
    super.onDestroy()
  }

  private fun addImage(root: FrameLayout, uriText: String) {
    val image = ImageView(this).apply {
      scaleType = ImageView.ScaleType.FIT_CENTER
      setImageResource(R.drawable.pte_im_ui_chat_message_image)
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

  private fun addVideo(root: FrameLayout, uriText: String) {
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
    val controller = MediaController(this)
    root.addView(VideoView(this).apply {
      val uri = Uri.parse(uriText)
      setVideoURI(uri)
      setMediaController(controller)
      setOnPreparedListener { player ->
        player.isLooping = false
        start()
        controller.show()
      }
    }, FrameLayout.LayoutParams(-1, -1, Gravity.CENTER))
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
