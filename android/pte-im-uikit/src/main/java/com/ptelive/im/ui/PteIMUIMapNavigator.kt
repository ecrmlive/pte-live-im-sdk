package com.ptelive.im.ui

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.ptelive.im.PteIMLocation

/**
 * Opens a received location in the first supported map client. No provider key
 * is required by UIKit and no location is uploaded by this helper.
 */
object PteIMUIMapNavigator {
  private data class MapCandidate(val label: String, val packageName: String?, val uri: Uri)

  /**
   * Priority is intentional: AMap → Baidu → Tencent → Google → system maps.
   * The chooser only includes applications actually installed on the device.
   * Returns false only if Android has no compatible map handler at all.
   */
  fun open(context: Context, location: PteIMLocation): Boolean {
    val label = Uri.encode(location.name.ifBlank { location.address.orEmpty() })
    val latitude = location.latitude
    val longitude = location.longitude
    val candidates = listOf(
      MapCandidate(
        "高德地图",
        "com.autonavi.minimap",
        Uri.parse("androidamap://route?sourceApplication=PteIMUIKit&dlat=$latitude&dlon=$longitude&dname=$label&dev=0&t=0"),
      ),
      MapCandidate(
        "百度地图",
        "com.baidu.BaiduMap",
        Uri.parse("baidumap://map/direction?destination=latlng:$latitude,$longitude|name:$label&mode=driving&src=PteIMUIKit"),
      ),
      MapCandidate(
        "腾讯地图",
        "com.tencent.map",
        Uri.parse("qqmap://map/routeplan?type=drive&tocoord=$latitude,$longitude&to=$label&referer=PteIMUIKit"),
      ),
      MapCandidate(
        "Google 地图",
        "com.google.android.apps.maps",
        Uri.parse("google.navigation:q=$latitude,$longitude"),
      ),
    )
    val available = candidates.mapNotNull { candidate ->
      Intent(Intent.ACTION_VIEW, candidate.uri).setPackage(candidate.packageName)
        .takeIf { it.resolveActivity(context.packageManager) != null }
        ?.let { candidate.label to it }
    }.toMutableList()
    Intent(Intent.ACTION_VIEW, Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude($label)"))
      .takeIf { it.resolveActivity(context.packageManager) != null }
      ?.let { available += "系统地图" to it }
    if (available.isEmpty()) {
      PteIMUINotice.error(context, "No supported map app installed")
      return false
    }
    if (context !is Activity) return launch(context, available.first().second)
    AlertDialog.Builder(context)
      .setTitle("选择导航应用")
      .setItems(available.map { it.first }.toTypedArray()) { _, index -> launch(context, available[index].second) }
      .setNegativeButton("取消", null)
      .show()
    return true
  }

  private fun launch(context: Context, intent: Intent): Boolean = runCatching {
    if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
  }.isSuccess
}
