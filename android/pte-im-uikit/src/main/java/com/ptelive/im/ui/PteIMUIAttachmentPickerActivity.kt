package com.ptelive.im.ui

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.location.Location
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import com.ptelive.im.PteIMLocation
import com.ptelive.im.PteIMMessage
import com.ptelive.im.PteIMSDK
import java.util.UUID
import java.util.concurrent.Executors

/**
 * UIKit-owned attachment workflow. It deliberately uses a small private
 * activity so a host using [PteIMUIChatView] does not need to forward an
 * ActivityResult or write picker boilerplate for standard IM attachments.
 */
internal object PteIMUIAttachmentBridge {
  private data class Pending(
    val client: PteIMSDK,
    val conversationId: String,
    val action: PteIMUIAction,
    val onError: (Throwable) -> Unit,
    val onQueued: (PteIMMessage, Uri) -> Unit,
  )

  private val pending = linkedMapOf<String, Pending>()
  private val executor = Executors.newCachedThreadPool()

  fun launch(
    context: Context,
    client: PteIMSDK,
    conversationId: String,
    action: PteIMUIAction,
    onError: (Throwable) -> Unit,
    onQueued: (PteIMMessage, Uri) -> Unit = { _, _ -> },
  ) {
    val token = UUID.randomUUID().toString()
    pending[token] = Pending(client, conversationId, action, onError, onQueued)
    val intent = Intent(context, PteIMUIAttachmentPickerActivity::class.java).putExtra(PteIMUIAttachmentPickerActivity.EXTRA_TOKEN, token)
    if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
  }

  fun action(token: String): PteIMUIAction? = pending[token]?.action

  fun completeMedia(token: String, uri: Uri) {
    val value = pending.remove(token) ?: return
    executor.execute {
      runCatching {
        val message = when (value.action) {
          PteIMUIAction.IMAGE, PteIMUIAction.CAMERA -> value.client.uploadAndSendImage(value.conversationId, uri)
          PteIMUIAction.VIDEO -> value.client.uploadAndSendVideo(value.conversationId, uri)
          PteIMUIAction.FILE -> value.client.uploadAndSendFile(value.conversationId, uri)
          else -> error("Unsupported UIKit media action: ${value.action}")
        }
        value.onQueued(message, uri)
      }.onFailure(value.onError)
    }
  }

  fun completeLocation(token: String, location: Location) {
    completeLocation(token, PteIMLocation(location.latitude, location.longitude, "Current location", null))
  }

  /** Finishes UIKit's location-picker flow with a selected or searched place. */
  fun completeLocation(token: String, location: PteIMLocation) {
    val value = pending.remove(token) ?: return
    runCatching {
      value.client.sendLocation(value.conversationId, location)
    }.onFailure(value.onError)
  }

  fun fail(token: String, error: Throwable) { pending.remove(token)?.onError?.invoke(error) }
  fun cancel(token: String) { pending.remove(token) }
}

/** Internal result host merged from PteIMUIKit's AndroidManifest. */
class PteIMUIAttachmentPickerActivity : Activity() {
  companion object {
    const val EXTRA_TOKEN = "pte.im.ui.attachment.token"
    private const val REQUEST_DOCUMENT = 8101
    private const val REQUEST_CAMERA = 8102
  }

  private val token: String by lazy { intent.getStringExtra(EXTRA_TOKEN).orEmpty() }
  private var cameraOutput: Uri? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    cameraOutput = savedInstanceState?.getParcelable("cameraOutput")
    if (token.isBlank() || PteIMUIAttachmentBridge.action(token) == null) { finish(); return }
    when (PteIMUIAttachmentBridge.action(token)) {
      PteIMUIAction.IMAGE -> openDocument("image/*")
      PteIMUIAction.VIDEO -> openDocument("video/*")
      PteIMUIAction.FILE -> openDocument("*/*")
      PteIMUIAction.CAMERA -> openCamera()
      PteIMUIAction.LOCATION -> openLocationPicker()
      else -> fail(IllegalArgumentException("Unsupported UIKit attachment"))
    }
  }

  override fun onSaveInstanceState(outState: Bundle) {
    super.onSaveInstanceState(outState)
    cameraOutput?.let { outState.putParcelable("cameraOutput", it) }
  }

  private fun openDocument(mimeType: String) {
    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
      type = mimeType
      addCategory(Intent.CATEGORY_OPENABLE)
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
    }, REQUEST_DOCUMENT)
  }

  private fun openCamera() {
    val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
      put(MediaStore.Images.Media.DISPLAY_NAME, "pte-im-${System.currentTimeMillis()}.jpg")
      put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
    }) ?: run { fail(IllegalStateException("Cannot create camera output")); return }
    cameraOutput = uri
    startActivityForResult(Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
      putExtra(MediaStore.EXTRA_OUTPUT, uri)
      addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }, REQUEST_CAMERA)
  }

  private fun openLocationPicker() {
    startActivity(Intent(this, PteIMUILocationPickerActivity::class.java)
      .putExtra(PteIMUILocationPickerActivity.EXTRA_TOKEN, token))
    finish()
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    when (requestCode) {
      REQUEST_DOCUMENT -> if (resultCode == RESULT_OK && data?.data != null) {
        val uri = data.data!!
        runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        PteIMUIAttachmentBridge.completeMedia(token, uri)
      } else PteIMUIAttachmentBridge.cancel(token)
      REQUEST_CAMERA -> if (resultCode == RESULT_OK && cameraOutput != null) PteIMUIAttachmentBridge.completeMedia(token, cameraOutput!!)
      else PteIMUIAttachmentBridge.cancel(token)
    }
    finish()
  }

  private fun fail(error: Throwable) { PteIMUIAttachmentBridge.fail(token, error); finish() }
}
