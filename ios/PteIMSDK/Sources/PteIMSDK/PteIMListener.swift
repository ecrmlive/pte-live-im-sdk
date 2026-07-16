import Foundation

/**
 A separately registered Core event receiver. A client can have a business
 listener plus multiple PteIMUIKit surfaces at the same time; no subscriber
 replaces another subscriber's callbacks.
 */
public final class PteIMListener: @unchecked Sendable {
  public var onConnectionChanged: ((Bool) -> Void)?
  public var onMessage: ((PteIMMessage) -> Void)?
  public var onMessageStateChanged: ((String, PteIMSendState) -> Void)?
  public var onUserSigWillExpire: (() -> Void)?
  public var onUserSigExpired: (() -> Void)?
  public var onThemeModeChanged: ((PteIMThemeMode) -> Void)?
  public var onLanguageChanged: ((PteIMLanguage) -> Void)?
  public var onError: ((Error) -> Void)?
  public var onStateChanges: (([PteIMStateChange]) -> Void)?

  public init() {}
}
