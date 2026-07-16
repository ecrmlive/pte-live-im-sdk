@_exported import PteIMSDK
import UIKit

/** Entry point for the native iOS UI Kit. It deliberately receives an already-logged-in Core client. */
public enum PteIMUIkit {
  public static func makeConversationListViewController(client: PteIMSDK, skin: PteIMUISkin = .default) -> PteIMUIConversationListViewController {
    PteIMUIConversationListViewController(client: client, skin: skin)
  }
  public static func makeContactListViewController(client: PteIMSDK, skin: PteIMUISkin = .default) -> PteIMUIContactListViewController {
    PteIMUIContactListViewController(client: client, skin: skin)
  }
  public static func makeChatViewController(client: PteIMSDK, conversationId: String, title: String? = nil, skin: PteIMUISkin = .default) -> PteIMUIChatViewController {
    PteIMUIChatViewController(client: client, conversationId: conversationId, title: title, skin: skin)
  }
}
