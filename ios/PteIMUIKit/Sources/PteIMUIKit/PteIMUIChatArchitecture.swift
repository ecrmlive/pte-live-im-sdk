import UIKit
import PteIMSDK

/**
 MessageKit-style renderer boundary for PteIMUIKit.

 A renderer owns one or more message kinds, its reuse identifier and cell
 configuration. Apps can replace the default renderers from
 `makeMessageRenderers()` without forking the conversation controller.
 */
@MainActor public protocol PteIMUIChatMessageRenderer: AnyObject {
  var reuseIdentifier: String { get }
  func supports(_ message: PteIMMessage) -> Bool
  func register(in tableView: UITableView)
  func configure(cell: UITableViewCell, message: PteIMMessage, outgoing: Bool, in chat: PteIMUIChatViewController, at indexPath: IndexPath)
}

/** Handles text and emoji messages in the default chat timeline. */
@MainActor open class PteIMUIBasicMessageRenderer: PteIMUIChatMessageRenderer {
  public init() {}
  open var reuseIdentifier: String { PteIMUIMessageCell.reuseIdentifier }
  open func supports(_ message: PteIMMessage) -> Bool {
    switch message.type {
    case .text, .emoji: return true
    default: return false
    }
  }
  open func register(in tableView: UITableView) {
    tableView.register(PteIMUIMessageCell.self, forCellReuseIdentifier: reuseIdentifier)
  }
  open func configure(cell: UITableViewCell, message: PteIMMessage, outgoing: Bool, in chat: PteIMUIChatViewController, at indexPath: IndexPath) {
    (cell as? PteIMUIMessageCell)?.configure(message: message, outgoing: outgoing, theme: chat.theme, language: chat.language, style: chat.skin.chat, senderName: chat.senderDisplayName(for: message), reactions: chat.reactions(for: message))
  }
}

/** Keeps voice messages independent from generic text-bubble typography. */
@MainActor open class PteIMUIVoiceMessageRenderer: PteIMUIChatMessageRenderer {
  public init() {}
  open var reuseIdentifier: String { PteIMUIVoiceMessageCell.reuseIdentifier }
  open func supports(_ message: PteIMMessage) -> Bool { message.type == .voice }
  open func register(in tableView: UITableView) {
    tableView.register(PteIMUIVoiceMessageCell.self, forCellReuseIdentifier: reuseIdentifier)
  }
  open func configure(cell: UITableViewCell, message: PteIMMessage, outgoing: Bool, in chat: PteIMUIChatViewController, at indexPath: IndexPath) {
    (cell as? PteIMUIVoiceMessageCell)?.configure(message: message, outgoing: outgoing, theme: chat.theme, language: chat.language, style: chat.skin.chat, senderName: chat.senderDisplayName(for: message), reactions: chat.reactions(for: message))
  }
}

/** Handles media and business cards using the bundled chat artwork. */
@MainActor open class PteIMUIRichMessageRenderer: PteIMUIChatMessageRenderer {
  public init() {}
  open var reuseIdentifier: String { PteIMUIRichMessageCell.reuseIdentifier }
  open func supports(_ message: PteIMMessage) -> Bool {
    switch message.type {
    case .image, .video, .location, .gift, .red_packet, .order, .file: return true
    default: return false
    }
  }
  open func register(in tableView: UITableView) {
    tableView.register(PteIMUIRichMessageCell.self, forCellReuseIdentifier: reuseIdentifier)
  }
  open func configure(cell: UITableViewCell, message: PteIMMessage, outgoing: Bool, in chat: PteIMUIChatViewController, at indexPath: IndexPath) {
    (cell as? PteIMUIRichMessageCell)?.configure(message: message, outgoing: outgoing, theme: chat.theme, language: chat.language, style: chat.skin.chat, senderName: chat.senderDisplayName(for: message), iconProvider: chat.skin.icons, reactions: chat.reactions(for: message))
  }
}

/**
 Input-bar event surface. The text event is also emitted for the keyboard's
 native `Send` key (`UITextField.returnKeyType = .send`).
 */
@MainActor public protocol PteIMUIInputBarDelegate: AnyObject {
  func inputBar(_ inputBar: PteIMUIInputBar, didSendText text: String)
  func inputBar(_ inputBar: PteIMUIInputBar, didSelect action: PteIMUIInputBarAction)
  func inputBar(_ inputBar: PteIMUIInputBar, voiceRecordingChanged isRecording: Bool)
  func inputBarDidCancelVoiceRecording(_ inputBar: PteIMUIInputBar)
}

public extension PteIMUIInputBarDelegate {
  func inputBar(_ inputBar: PteIMUIInputBar, didSendText text: String) {}
  func inputBar(_ inputBar: PteIMUIInputBar, didSelect action: PteIMUIInputBarAction) {}
  func inputBar(_ inputBar: PteIMUIInputBar, voiceRecordingChanged isRecording: Bool) {}
  func inputBarDidCancelVoiceRecording(_ inputBar: PteIMUIInputBar) {}
}
