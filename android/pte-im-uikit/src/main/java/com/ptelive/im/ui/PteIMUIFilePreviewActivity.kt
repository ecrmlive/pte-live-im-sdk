package com.ptelive.im.ui

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.ptelive.im.PteIMMessage
import java.net.URL
import java.util.concurrent.Executors

/**
 * UIKit's dependency-free file preview hand-off. It deliberately keeps the
 * actual renderer replaceable: hosts may subclass it for PDF/Office viewers
 * while this default surface provides open and long-press system-file saving.
 */
open class PteIMUIFilePreviewActivity : Activity() {
  companion object {
    const val EXTRA_URI = "pte.im.ui.file.uri"
    const val EXTRA_NAME = "pte.im.ui.file.name"
    const val EXTRA_MIME = "pte.im.ui.file.mime"

    fun open(
      context: Context,
      message: PteIMMessage,
      activityClass: Class<out Activity> = PteIMUIFilePreviewActivity::class.java,
    ) {
      val intent = Intent(context, activityClass)
        .putExtra(EXTRA_URI, message.media?.url.orEmpty())
        .putExtra(EXTRA_NAME, message.media?.fileName.orEmpty())
        .putExtra(EXTRA_MIME, message.media?.mimeType.orEmpty())
      if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
    }
  }

  private val executor = Executors.newSingleThreadExecutor()

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    window.statusBarColor = Color.rgb(8, 8, 31)
    window.navigationBarColor = Color.rgb(8, 8, 31)
    val uri = intent.getStringExtra(EXTRA_URI).orEmpty()
    val name = intent.getStringExtra(EXTRA_NAME).orEmpty().ifBlank { "PteIM file" }
    val mime = intent.getStringExtra(EXTRA_MIME).orEmpty().ifBlank { "application/octet-stream" }
    val root = FrameLayout(this).apply { setBackgroundColor(Color.rgb(8, 8, 31)) }
    setContentView(root)
    root.addView(previewContent(name, uri, mime), FrameLayout.LayoutParams(-1, -1))
    root.addView(ImageButton(this).apply {
      setImageResource(R.drawable.pte_im_ui_chat_back)
      setColorFilter(Color.WHITE)
      setBackgroundColor(Color.TRANSPARENT)
      setOnClickListener { finish() }
    }, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.START).apply { leftMargin = dp(12); topMargin = dp(8) })
  }

  /** Override for an in-app document renderer without changing file actions. */
  protected open fun previewContent(name: String, uri: String, mime: String): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    gravity = Gravity.CENTER
    setPadding(dp(36), dp(36), dp(36), dp(36))
    setOnLongClickListener { saveToDownloads(uri, name, mime); true }
    addView(ImageView(this@PteIMUIFilePreviewActivity).apply {
      setImageResource(R.drawable.pte_im_ui_chat_action_file)
      scaleType = ImageView.ScaleType.FIT_CENTER
    }, LinearLayout.LayoutParams(dp(72), dp(72)).apply { gravity = Gravity.CENTER_HORIZONTAL })
    addView(TextView(this@PteIMUIFilePreviewActivity).apply {
      text = name
      setTextColor(Color.WHITE)
      textSize = 18f
      gravity = Gravity.CENTER
      setPadding(0, dp(18), 0, dp(8))
    })
    addView(TextView(this@PteIMUIFilePreviewActivity).apply {
      text = "点击打开预览 · 长按保存到系统文件"
      setTextColor(Color.rgb(184, 190, 220))
      textSize = 13f
      gravity = Gravity.CENTER
      setOnClickListener { openExternal(uri, mime) }
    })
  }

  protected open fun openExternal(uriText: String, mime: String) {
    if (uriText.isBlank()) {
      PteIMUINotice.error(this, "文件不可用")
      return
    }
    runCatching {
      startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uriText)).apply {
        setDataAndType(Uri.parse(uriText), mime)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      })
    }.onFailure { PteIMUINotice.error(this, "没有可用的文件预览应用") }
  }

  protected open fun saveToDownloads(uriText: String, name: String, mime: String) {
    if (uriText.isBlank()) return
    executor.execute {
      runCatching {
        val destination = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
          put(MediaStore.Downloads.DISPLAY_NAME, name)
          put(MediaStore.Downloads.MIME_TYPE, mime)
        }) ?: error("Cannot create download destination")
        val source = when (Uri.parse(uriText).scheme) {
          "content", "file" -> contentResolver.openInputStream(Uri.parse(uriText))
          else -> URL(uriText).openConnection().getInputStream()
        } ?: error("Cannot open file")
        source.use { input -> contentResolver.openOutputStream(destination)?.use { output -> input.copyTo(output) } ?: error("Cannot write file") }
      }.onSuccess { runOnUiThread { PteIMUINotice.success(this, "已保存到系统文件") } }
        .onFailure { error -> runOnUiThread { PteIMUINotice.error(this, error.message ?: "保存失败") } }
    }
  }

  override fun onDestroy() {
    executor.shutdownNow()
    super.onDestroy()
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
