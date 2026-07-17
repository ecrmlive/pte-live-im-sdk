package com.ptelive.im.uidemo

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowInsets
import android.widget.FrameLayout
import android.widget.ImageView

/**
 * Full-screen brand launch surface. Android's system splash prevents a cold
 * start flash; this activity then displays the supplied, uncropped artboard
 * before handing off to the independent business-login flow.
 */
class PteIMUIDemoSplashActivity : Activity() {
  private val handler = Handler(Looper.getMainLooper())
  private val openDemo = Runnable {
    startActivity(Intent(this, PteIMUIDemoActivity::class.java))
    overridePendingTransition(0, 0)
    finish()
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    window.statusBarColor = Color.TRANSPARENT
    window.navigationBarColor = Color.TRANSPARENT
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
      window.setDecorFitsSystemWindows(false)
    } else {
      @Suppress("DEPRECATION")
      window.decorView.systemUiVisibility =
        View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
          View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
          View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
          View.SYSTEM_UI_FLAG_FULLSCREEN or
          View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
    }
    setContentView(FrameLayout(this).apply {
      // Both supplied launch assets are kept independently: the background
      // remains full-bleed while the composed artboard preserves its original
      // typography, logo and constellation placement on every device.
      setBackgroundColor(Color.rgb(16, 10, 44))
      addView(ImageView(this@PteIMUIDemoSplashActivity).apply {
        setImageResource(R.drawable.pte_im_ui_splash_background)
        scaleType = ImageView.ScaleType.CENTER_CROP
      }, FrameLayout.LayoutParams(-1, -1))
      addView(ImageView(this@PteIMUIDemoSplashActivity).apply {
        setImageResource(R.drawable.pte_im_ui_splash_art)
        // Source artboard is 376 × 773. CENTER_CROP preserves its exact
        // proportions and only trims symmetric outer pixels on taller phones.
        scaleType = ImageView.ScaleType.CENTER_CROP
        contentDescription = "PteIMUIDemo"
      }, FrameLayout.LayoutParams(-1, -1))
    })
    hideSystemBars()
  }

  override fun onResume() {
    super.onResume()
    hideSystemBars()
    handler.postDelayed(openDemo, minimumBrandDurationMs)
  }

  override fun onWindowFocusChanged(hasFocus: Boolean) {
    super.onWindowFocusChanged(hasFocus)
    if (hasFocus) hideSystemBars()
  }

  override fun onPause() {
    handler.removeCallbacks(openDemo)
    super.onPause()
  }

  override fun onDestroy() {
    handler.removeCallbacks(openDemo)
    super.onDestroy()
  }

  private companion object {
    const val minimumBrandDurationMs = 850L
  }

  private fun hideSystemBars() {
    @Suppress("DEPRECATION")
    window.decorView.systemUiVisibility =
      View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
        View.SYSTEM_UI_FLAG_FULLSCREEN or
        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
      // A splash theme has not attached a DecorView at the start of onCreate.
      // Posting guarantees that the controller exists on Android 12+.
      window.decorView.post {
        window.decorView.windowInsetsController?.hide(
          WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars(),
        )
      }
    }
  }
}
