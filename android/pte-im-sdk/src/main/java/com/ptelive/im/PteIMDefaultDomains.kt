package com.ptelive.im

/**
 * Public test/prod defaults for [PteIMBaseConfig]. Host apps may override any
 * field when calling [PteIMSDK.configure]; omit a field to keep the default.
 */
object PteIMDefaultDomains {
  const val API: String = "https://api-im.qxkejiwl.top"
  const val IM: String = "wss://wss.qxkejiwl.top/ws"
  const val COS: String = "https://cos.qxkejiwl.top"
  const val COMMERCE: String = "https://api-im-commerce.qxkejiwl.top"
}
