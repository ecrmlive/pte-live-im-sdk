package com.ptelive.im.ui

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.location.Address
import android.location.Geocoder
import android.location.LocationManager
import android.os.Bundle
import android.os.CancellationSignal
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.ptelive.im.PteIMLocation
import java.util.Locale
import java.util.concurrent.Executors

/**
 * UIKit's dependency-free place picker. Android does not offer a standard
 * map-selection Activity, so this screen combines current location, geocoder
 * search and editable coordinates without binding PteIMUIKit to a map vendor.
 * Hosts which use a map SDK can subclass/replace this Activity and complete the
 * same [PteIMUIAttachmentBridge] token with their selected [PteIMLocation].
 */
open class PteIMUILocationPickerActivity : Activity() {
  companion object {
    const val EXTRA_TOKEN = "pte.im.ui.location.token"
    private const val REQUEST_LOCATION = 8121
  }

  private val executor = Executors.newSingleThreadExecutor()
  private val token: String by lazy { intent.getStringExtra(EXTRA_TOKEN).orEmpty() }
  private lateinit var titleInput: EditText
  private lateinit var addressInput: EditText
  private lateinit var latitudeInput: EditText
  private lateinit var longitudeInput: EditText
  private lateinit var status: TextView
  private var bridgeFinished = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    if (token.isBlank() || PteIMUIAttachmentBridge.action(token) != PteIMUIAction.LOCATION) {
      finish()
      return
    }
    window.statusBarColor = Color.rgb(8, 8, 31)
    window.navigationBarColor = Color.rgb(8, 8, 31)
    setContentView(content())
  }

  override fun onDestroy() {
    // A system Back gesture or an interrupted picker must not leave the
    // attachment bridge waiting forever for a result token.
    if (!bridgeFinished && !isChangingConfigurations) PteIMUIAttachmentBridge.cancel(token)
    executor.shutdownNow()
    super.onDestroy()
  }

  @Deprecated("Deprecated in Java")
  override fun onBackPressed() = cancel()

  /** Replace this whole screen when an app has a licensed map picker. */
  protected open fun content(): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    setBackgroundColor(Color.rgb(8, 8, 31))
    addView(navigation(), LinearLayout.LayoutParams(-1, dp(44)))
    addView(ScrollView(this@PteIMUILocationPickerActivity).apply {
      addView(LinearLayout(this@PteIMUILocationPickerActivity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(24), dp(20), dp(28))
        addView(TextView(this@PteIMUILocationPickerActivity).apply {
          text = "选择位置"
          textSize = 22f
          setTextColor(Color.WHITE)
        })
        addView(TextView(this@PteIMUILocationPickerActivity).apply {
          text = "可使用当前位置、搜索地点，或手动确认坐标"
          textSize = 13f
          setTextColor(Color.rgb(174, 183, 214))
          setPadding(0, dp(8), 0, dp(18))
        })
        addView(primaryButton("使用当前位置") { requestCurrentLocation() }, match().apply { bottomMargin = dp(14) })
        titleInput = input("地点名称，例如：张江科技园")
        addView(labeled("地点名称", titleInput), match().apply { bottomMargin = dp(12) })
        addressInput = input("地址或搜索关键字")
        addView(labeled("地址 / 搜索", addressInput), match().apply { bottomMargin = dp(10) })
        addView(secondaryButton("搜索并填充坐标") { searchPlace() }, match().apply { bottomMargin = dp(18) })
        latitudeInput = input("31.2304", decimal = true)
        addView(labeled("纬度", latitudeInput), match().apply { bottomMargin = dp(12) })
        longitudeInput = input("121.4737", decimal = true)
        addView(labeled("经度", longitudeInput), match().apply { bottomMargin = dp(12) })
        status = TextView(this@PteIMUILocationPickerActivity).apply {
          textSize = 12f
          setTextColor(Color.rgb(174, 183, 214))
          minHeight = dp(28)
          gravity = Gravity.CENTER_VERTICAL
        }
        addView(status, match().apply { bottomMargin = dp(12) })
        addView(primaryButton("发送位置") { confirmSelection() }, match())
      }, LinearLayout.LayoutParams(-1, -2))
    }, LinearLayout.LayoutParams(-1, 0, 1f))
  }

  /** Override only the top bar while retaining the selection implementation. */
  protected open fun navigation(): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(8), 0, dp(8), 0)
    addView(ImageButton(this@PteIMUILocationPickerActivity).apply {
      setImageResource(R.drawable.pte_im_ui_chat_back)
      setColorFilter(Color.WHITE)
      setBackgroundColor(Color.TRANSPARENT)
      setPadding(0, 0, 0, 0)
      setOnClickListener { cancel() }
    }, LinearLayout.LayoutParams(dp(44), dp(44)))
    addView(TextView(this@PteIMUILocationPickerActivity).apply {
      text = "位置"
      textSize = 16f
      setTextColor(Color.WHITE)
      gravity = Gravity.CENTER_VERTICAL
    }, LinearLayout.LayoutParams(0, dp(44), 1f))
  }

  /** Uses Android geocoding when available; users can always amend the result. */
  protected open fun searchPlace() {
    val query = addressInput.text.toString().trim().ifBlank { titleInput.text.toString().trim() }
    if (query.isBlank()) {
      PteIMUINotice.info(this, "请输入地点或地址")
      return
    }
    status.text = "正在搜索地点…"
    executor.execute {
      val result = runCatching {
        if (!Geocoder.isPresent()) error("当前设备不支持地点搜索")
        @Suppress("DEPRECATION")
        Geocoder(this, Locale.getDefault()).getFromLocationName(query, 1).orEmpty().firstOrNull()
          ?: error("未找到地点")
      }
      runOnUiThread {
        result.onSuccess(::applyAddress).onFailure {
          status.text = it.message ?: "地点搜索失败"
          PteIMUINotice.error(this, status.text.toString())
        }
      }
    }
  }

  /** Requests only the normal foreground location permission, then fills the editable fields. */
  protected open fun requestCurrentLocation() {
    if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
      checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), REQUEST_LOCATION)
      return
    }
    status.text = "正在获取当前位置…"
    val manager = getSystemService(LocationManager::class.java)
    val provider = when {
      manager.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
      manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
      else -> null
    }
    if (provider == null) {
      status.text = "未开启定位服务"
      PteIMUINotice.error(this, status.text.toString())
      return
    }
    manager.getCurrentLocation(provider, CancellationSignal(), mainExecutor) { location ->
      if (location == null) {
        status.text = "当前位置不可用"
        PteIMUINotice.error(this, status.text.toString())
      } else {
        latitudeInput.setText(location.latitude.toString())
        longitudeInput.setText(location.longitude.toString())
        titleInput.setText(titleInput.text.toString().ifBlank { "当前位置" })
        status.text = "已填入当前位置，可确认发送"
      }
    }
  }

  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == REQUEST_LOCATION && grantResults.any { it == PackageManager.PERMISSION_GRANTED }) requestCurrentLocation()
    else if (requestCode == REQUEST_LOCATION) PteIMUINotice.error(this, "未授权定位权限")
  }

  /** Validates the selected point then delegates message send to Core via the bridge. */
  protected open fun confirmSelection() {
    val latitude = latitudeInput.text.toString().toDoubleOrNull()
    val longitude = longitudeInput.text.toString().toDoubleOrNull()
    if (latitude == null || longitude == null || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
      PteIMUINotice.error(this, "请输入有效的经纬度")
      return
    }
    val name = titleInput.text.toString().trim().ifBlank { "位置" }
    val address = addressInput.text.toString().trim().ifBlank { null }
    PteIMUIAttachmentBridge.completeLocation(token, PteIMLocation(latitude, longitude, name, address))
    bridgeFinished = true
    finish()
  }

  private fun applyAddress(address: Address) {
    latitudeInput.setText(address.latitude.toString())
    longitudeInput.setText(address.longitude.toString())
    val feature = address.featureName?.takeIf { it.isNotBlank() }
      ?: address.locality?.takeIf { it.isNotBlank() }
      ?: "位置"
    titleInput.setText(titleInput.text.toString().ifBlank { feature })
    addressInput.setText(address.getAddressLine(0).orEmpty())
    status.text = "已找到位置，可确认发送"
  }

  private fun labeled(label: String, input: EditText): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    addView(TextView(this@PteIMUILocationPickerActivity).apply {
      text = label
      textSize = 12f
      setTextColor(Color.rgb(222, 226, 246))
      setPadding(0, 0, 0, dp(6))
    })
    addView(input, match())
  }

  private fun input(hint: String, decimal: Boolean = false): EditText = EditText(this).apply {
    this.hint = hint
    setSingleLine(true)
    textSize = 14f
    setTextColor(Color.WHITE)
    setHintTextColor(Color.rgb(139, 150, 188))
    inputType = if (decimal) android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL or android.text.InputType.TYPE_NUMBER_FLAG_SIGNED else android.text.InputType.TYPE_CLASS_TEXT
    setPadding(dp(12), 0, dp(12), 0)
    background = rounded(Color.rgb(31, 32, 79), Color.rgb(54, 50, 108), 12)
  }

  private fun primaryButton(label: String, action: () -> Unit): Button = Button(this).apply {
    text = label
    isAllCaps = false
    textSize = 15f
    setTextColor(Color.WHITE)
    background = rounded(Color.rgb(129, 68, 241), Color.TRANSPARENT, 14)
    setOnClickListener { action() }
  }

  private fun secondaryButton(label: String, action: () -> Unit): Button = Button(this).apply {
    text = label
    isAllCaps = false
    textSize = 14f
    setTextColor(Color.rgb(205, 190, 255))
    background = rounded(Color.rgb(31, 32, 79), Color.rgb(74, 60, 133), 14)
    setOnClickListener { action() }
  }

  private fun cancel() {
    PteIMUIAttachmentBridge.cancel(token)
    bridgeFinished = true
    finish()
  }

  private fun match() = LinearLayout.LayoutParams(-1, dp(48))
  private fun rounded(fill: Int, stroke: Int, radius: Int) = android.graphics.drawable.GradientDrawable().apply {
    setColor(fill)
    setStroke(dp(1), stroke)
    cornerRadius = dp(radius).toFloat()
  }
  private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
