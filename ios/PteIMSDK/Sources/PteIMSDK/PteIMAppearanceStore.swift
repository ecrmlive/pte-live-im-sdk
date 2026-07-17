import Foundation

/**
 Stores UI-only preferences separately from credentials and message cache.
 Preferences are scoped to the SDK endpoint, app ID, and IM user, so one
 account's manual choice never changes another account's presentation.
 */
final class PteIMAppearanceStore {
  private let defaults: UserDefaults?
  private let key: String

  init(storeKey: String, persistent: Bool) {
    defaults = persistent ? .standard : nil
    key = "com.ptelive.im.appearance." + Data(storeKey.utf8).base64EncodedString()
  }

  func load() -> PteIMAppearance? {
    guard let values = defaults?.dictionary(forKey: key),
          let themeValue = values["themeMode"] as? String,
          let languageValue = values["language"] as? String,
          let themeMode = PteIMThemeMode(rawValue: themeValue),
          let language = PteIMLanguage(rawValue: languageValue) else { return nil }
    return PteIMAppearance(themeMode: themeMode, language: language)
  }

  func save(_ appearance: PteIMAppearance) {
    defaults?.set([
      "themeMode": appearance.themeMode.rawValue,
      "language": appearance.language.rawValue
    ], forKey: key)
  }

  func remove() { defaults?.removeObject(forKey: key) }
}
