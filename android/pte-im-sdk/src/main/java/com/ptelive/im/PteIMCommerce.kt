package com.ptelive.im

import org.json.JSONArray
import org.json.JSONObject

/**
 * First-party IM Commerce extension. It shares the SDK's UserSig but owns no
 * WebSocket: room delivery is performed by Commerce -> IM scene outbox.
 */
class PteIMCommerce internal constructor(private val sdk: PteIMSDK) {
  fun capabilities(callback: (Result<PteIMCommerceCapability>) -> Unit) = request(callback) {
    val data = sdk.postCommerceJson("/v1/commerce/capabilities", JSONObject())
    PteIMCommerceCapability(data.optInt("version", 1), data.optString("currency", "COIN"), data.optBoolean("gifts"), data.optBoolean("backpack"), data.optBoolean("orders"), data.optBoolean("redPackets"))
  }

  fun gifts(callback: (Result<List<PteIMGift>>) -> Unit) = request(callback) {
    jsonList(sdk.postCommerceJson("/v1/commerce/gifts", JSONObject())) { PteIMGift.from(it) }
  }

  fun wallet(callback: (Result<PteIMWallet>) -> Unit) = request(callback) {
    PteIMWallet.from(sdk.postCommerceJson("/v1/commerce/wallet", JSONObject()))
  }

  fun backpack(callback: (Result<List<PteIMBackpackItem>>) -> Unit) = request(callback) {
    jsonList(sdk.postCommerceJson("/v1/commerce/backpack", JSONObject())) { PteIMBackpackItem.from(it) }
  }

  fun orders(limit: Int = 50, callback: (Result<List<PteIMCommerceOrder>>) -> Unit) = request(callback) {
    jsonList(sdk.postCommerceJson("/v1/commerce/orders", JSONObject().put("limit", limit))) { PteIMCommerceOrder.from(it) }
  }

  fun sendGift(request: PteIMGiftSendRequest, callback: (Result<PteIMCommerceOrder>) -> Unit) = request(callback) {
    PteIMCommerceOrder.from(sdk.postCommerceJson("/v1/commerce/gifts/send", request.toJson()))
  }

  fun useBackpack(request: PteIMBackpackUseRequest, callback: (Result<PteIMCommerceOrder>) -> Unit) = request(callback) {
    PteIMCommerceOrder.from(sdk.postCommerceJson("/v1/commerce/backpack/use", request.toJson()))
  }

  fun createRedPacket(request: PteIMRedPacketCreateRequest, callback: (Result<PteIMRedPacket>) -> Unit) = request(callback) {
    PteIMRedPacket.from(sdk.postCommerceJson("/v1/commerce/red-packets/create", request.toJson()))
  }

  fun redPacket(redPacketId: String, callback: (Result<PteIMRedPacketDetail>) -> Unit) = request(callback) {
    PteIMRedPacketDetail.from(sdk.postCommerceJson("/v1/commerce/red-packets/$redPacketId", JSONObject()))
  }

  fun claimRedPacket(redPacketId: String, callback: (Result<PteIMRedPacketDetail>) -> Unit) = request(callback) {
    PteIMRedPacketDetail.from(sdk.postCommerceJson("/v1/commerce/red-packets/$redPacketId/claim", JSONObject()))
  }

  private fun <T> request(callback: (Result<T>) -> Unit, action: () -> T) = sdk.executeCommerce { callback(runCatching(action)) }
  private fun <T> jsonList(value: JSONObject, mapper: (JSONObject) -> T): List<T> {
    val array = value.optJSONArray("list") ?: value.optJSONArray("data") ?: JSONArray()
    return (0 until array.length()).map { mapper(array.getJSONObject(it)) }
  }
}

data class PteIMCommerceCapability(val version: Int, val currency: String, val gifts: Boolean, val backpack: Boolean, val orders: Boolean, val redPackets: Boolean)
data class PteIMGift(val sku: String, val title: String, val coverUrl: String, val unitAmount: Long, val currency: String) { companion object { fun from(v: JSONObject) = PteIMGift(v.optString("sku"), v.optString("title"), v.optString("cover_url"), v.optLong("unit_amount"), v.optString("currency", "COIN")) } }
data class PteIMWallet(val balance: Long, val currency: String) { companion object { fun from(v: JSONObject) = PteIMWallet(v.optLong("balance"), v.optString("currency", "COIN")) } }
data class PteIMBackpackItem(val sku: String, val title: String, val coverUrl: String, val quantity: Long, val expiresAt: Long) { companion object { fun from(v: JSONObject) = PteIMBackpackItem(v.optString("sku"), v.optString("title"), v.optString("cover_url"), v.optLong("quantity"), v.optLong("expires_at")) } }
data class PteIMCommerceOrder(val orderId: String, val type: String, val resourceId: String, val amount: Long, val currency: String, val status: Int, val snapshot: String) { companion object { fun from(v: JSONObject) = PteIMCommerceOrder(v.optString("order_id"), v.optString("type"), v.optString("resource_id"), v.optLong("amount"), v.optString("currency", "COIN"), v.optInt("status"), v.optString("snapshot")) } }
data class PteIMRedPacket(val redPacketId: String, val roomId: String, val mode: String, val greeting: String, val totalAmount: Long, val totalCount: Int, val remainingAmount: Long, val remainingCount: Int, val currency: String, val status: Int, val expiresAt: Long) { companion object { fun from(v: JSONObject) = PteIMRedPacket(v.optString("red_packet_id"), v.optString("room_id"), v.optString("mode"), v.optString("greeting"), v.optLong("total_amount"), v.optInt("total_count"), v.optLong("remaining_amount"), v.optInt("remaining_count"), v.optString("currency", "COIN"), v.optInt("status"), v.optLong("expires_at")) } }
data class PteIMRedPacketClaim(val amount: Long) { companion object { fun from(v: JSONObject) = PteIMRedPacketClaim(v.optLong("amount")) } }
data class PteIMRedPacketDetail(val redPacket: PteIMRedPacket, val myClaim: PteIMRedPacketClaim?) { companion object { fun from(v: JSONObject): PteIMRedPacketDetail { val claim = if (v.has("myClaim") && !v.isNull("myClaim")) PteIMRedPacketClaim.from(v.getJSONObject("myClaim")) else if (v.has("claim")) PteIMRedPacketClaim.from(v.getJSONObject("claim")) else null; return PteIMRedPacketDetail(PteIMRedPacket.from(v.getJSONObject("redPacket")), claim) } } }
data class PteIMGiftSendRequest(val clientRequestId: String, val sku: String, val quantity: Long, val targetUserId: Long = 0, val sceneType: String = "", val roomId: String = "") { fun toJson() = JSONObject().put("clientRequestId", clientRequestId).put("sku", sku).put("quantity", quantity).put("targetUserId", targetUserId).put("sceneType", sceneType).put("roomId", roomId) }
data class PteIMBackpackUseRequest(val clientRequestId: String, val sku: String, val quantity: Long, val sceneType: String = "", val roomId: String = "") { fun toJson() = JSONObject().put("clientRequestId", clientRequestId).put("sku", sku).put("quantity", quantity).put("sceneType", sceneType).put("roomId", roomId) }
data class PteIMRedPacketCreateRequest(val clientRequestId: String, val roomId: String, val totalAmount: Long, val totalCount: Int, val mode: String = "lucky", val greeting: String = "", val sceneType: String = "live", val expiresIn: Long = 86400) { fun toJson() = JSONObject().put("clientRequestId", clientRequestId).put("roomId", roomId).put("totalAmount", totalAmount).put("totalCount", totalCount).put("mode", mode).put("greeting", greeting).put("sceneType", sceneType).put("expiresIn", expiresIn) }
