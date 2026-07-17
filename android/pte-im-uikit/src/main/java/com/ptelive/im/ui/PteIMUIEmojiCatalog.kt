package com.ptelive.im.ui

/**
 * The exact built-in set used by the OpenHarmony PteIMUIKit picker. Keeping
 * this list platform-identical means a system emoji message has the same
 * identifier and order on Android and Harmony.
 */
object PteIMUIEmojiCatalog {
  fun smileys(): List<String> = listOf(
    "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "☺", "😃", "😉", "😊",
    "😇", "😍", "😘", "😋", "😗", "😙", "😚", "😛", "😜", "😝", "😏", "😐",
    "😑", "😶", "🙄", "😬", "🤔", "😥", "😪", "😴", "😭", "😠", "😡", "😎",
    "🤓", "😷", "🤒", "🤕", "😵", "🤠", "🤡", "🤥", "🤤", "😱", "😨", "😰",
  )
}
