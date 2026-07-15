@_exported import PteLiveIM
import UIKit

/** Entry point for the native iOS UI Kit. It deliberately receives an already-logged-in Core client. */
public enum PteIMUIKit {
  public static func makeConversationListViewController(client: PteLiveIM, theme: PteIMUITheme = .default) -> PteIMUIConversationListViewController {
    PteIMUIConversationListViewController(client: client, theme: theme)
  }
  public static func makeChatViewController(client: PteLiveIM, conversationId: String, title: String? = nil, theme: PteIMUITheme = .default) -> PteIMUIChatViewController {
    PteIMUIChatViewController(client: client, conversationId: conversationId, title: title, theme: theme)
  }
}
