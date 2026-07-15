import PteLiveIM

public enum PteIMUILocalization {
  public static func value(_ zh: String, _ en: String, language: PteIMLanguage) -> String {
    language == .enUS ? en : zh
  }
}
