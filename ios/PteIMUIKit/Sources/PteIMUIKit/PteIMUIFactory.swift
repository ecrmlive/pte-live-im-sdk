@_exported import PteIMSDK
import UIKit

/** Entry point for the native iOS UI Kit. It deliberately receives an already-logged-in Core client. */
public enum PteIMUIkit {
  public static func makeConversationListViewController(client: PteIMSDK, theme: PteIMUITheme = .default) -> PteIMUIConversationListViewController {
    PteIMUIConversationListViewController(client: client, theme: theme)
  }
  public static func makeChatViewController(client: PteIMSDK, conversationId: String, title: String? = nil, theme: PteIMUITheme = .default) -> PteIMUIChatViewController {
    PteIMUIChatViewController(client: client, conversationId: conversationId, title: title, theme: theme)
  }
}
