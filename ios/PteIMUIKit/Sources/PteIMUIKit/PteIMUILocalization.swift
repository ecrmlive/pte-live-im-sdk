import PteIMSDK

public enum PteIMUILocalization {
  public static func value(_ zh: String, _ en: String, language: PteIMLanguage) -> String {
    language.resolved() == .enUS ? en : zh
  }
}
