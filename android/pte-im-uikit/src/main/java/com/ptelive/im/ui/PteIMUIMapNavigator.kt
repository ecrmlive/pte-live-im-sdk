package com.ptelive.im.ui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import com.ptelive.im.PteIMLocation

/**
 * Opens a received location in the first supported map client. No provider key
 * is required by UIKit and no location is uploaded by this helper.
 */
object PteIMUIMapNavigator {
  private data class MapCandidate(val packageName: String, val uri: Uri)

  /**
   * Priority is intentional: AMap → Baidu → Tencent → Google → system maps.
   * Returns false only if Android has no compatible map handler at all.
   */
  fun open(context: Context, location: PteIMLocation): Boolean {
    val label = Uri.encode(location.name.ifBlank { location.address.orEmpty() })
    val latitude = location.latitude
    val longitude = location.longitude
    val candidates = listOf(
      MapCandidate(
        "com.autonavi.minimap",
        Uri.parse("androidamap://route?sourceApplication=PteIMUIKit&dlat=$latitude&dlon=$longitude&dname=$label&dev=0&t=0"),
      ),
      MapCandidate(
        "com.baidu.BaiduMap",
        Uri.parse("baidumap://map/direction?destination=latlng:$latitude,$longitude|name:$label&mode=driving&src=PteIMUIKit"),
      ),
      MapCandidate(
        "com.tencent.map",
        Uri.parse("qqmap://map/routeplan?type=drive&tocoord=$latitude,$longitude&to=$label&referer=PteIMUIKit"),
      ),
      MapCandidate(
        "com.google.android.apps.maps",
        Uri.parse("google.navigation:q=$latitude,$longitude"),
      ),
    )
    candidates.forEach { candidate ->
      val intent = Intent(Intent.ACTION_VIEW, candidate.uri).setPackage(candidate.packageName)
      if (intent.resolveActivity(context.packageManager) != null && launch(context, intent)) return true
    }
    val systemIntent = Intent(
      Intent.ACTION_VIEW,
      Uri.parse("geo:$latitude,$longitude?q=$latitude,$longitude($label)"),
    )
    if (systemIntent.resolveActivity(context.packageManager) != null && launch(context, systemIntent)) return true
    Toast.makeText(context, "No supported map app installed", Toast.LENGTH_SHORT).show()
    return false
  }

  private fun launch(context: Context, intent: Intent): Boolean = runCatching {
    if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
  }.isSuccess
}
