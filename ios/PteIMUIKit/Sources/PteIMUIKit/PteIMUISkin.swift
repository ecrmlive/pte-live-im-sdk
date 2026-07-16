import UIKit

/** A complete, replaceable visual skin for the three PteIMUIKit surfaces. */
public final class PteIMUISkin {
  public var theme: PteIMUITheme
  public var list: PteIMUIListStyle
  public var chat: PteIMUIChatStyle
  public var icons: PteIMUIIconProvider

  public init(theme: PteIMUITheme = .default, list: PteIMUIListStyle = .default, chat: PteIMUIChatStyle = .default, icons: PteIMUIIconProvider = PteIMUISystemIconProvider()) {
    self.theme = theme; self.list = list; self.chat = chat; self.icons = icons
  }

  /// Returns a fresh mutable skin so changing one controller cannot recolour another.
  public static var `default`: PteIMUISkin { PteIMUISkin() }
}

/** Fonts, colours, spacing and separators used by both conversation and contact rows. */
public final class PteIMUIListStyle {
  public var rowHeight: CGFloat = 73
  public var horizontalInset: CGFloat = 20
  public var avatarSize: CGFloat = 42
  public var avatarFont: UIFont = .systemFont(ofSize: 15, weight: .bold)
  public var titleFont: UIFont = .systemFont(ofSize: 16, weight: .semibold)
  public var subtitleFont: UIFont = .systemFont(ofSize: 12, weight: .regular)
  public var timeFont: UIFont = .systemFont(ofSize: 11, weight: .regular)
  public var unreadFont: UIFont = .systemFont(ofSize: 11, weight: .bold)
  public var avatarTextColor: UIColor = .white
  public var titleColor: UIColor?
  public var subtitleColor: UIColor?
  public var timeColor: UIColor?
  public var unreadTextColor: UIColor = .white
  public var unreadBackgroundColor: UIColor?
  public var cellBackgroundColor: UIColor?
  public var separatorColor: UIColor?
  public var chevronColor: UIColor?
  public var showsSeparator: Bool = true
  public var showsChevron: Bool = true
  public var cellCornerRadius: CGFloat = 0
  public var cellInsets: UIEdgeInsets = .zero
  public init() {}
  public static var `default`: PteIMUIListStyle { PteIMUIListStyle() }
}

/** All visual knobs for the chat navigation, messages and composer. */
public final class PteIMUIChatStyle {
  public var navigationTitleFont: UIFont = .systemFont(ofSize: 16, weight: .semibold)
  public var navigationSubtitleFont: UIFont = .systemFont(ofSize: 11, weight: .regular)
  public var messageFont: UIFont = .systemFont(ofSize: 15, weight: .regular)
  public var messageMetaFont: UIFont = .systemFont(ofSize: 11, weight: .regular)
  public var navigationTitleColor: UIColor?
  public var incomingTextColor: UIColor?
  public var outgoingTextColor: UIColor?
  public var messageMetaColor: UIColor?
  public var incomingBubbleColor: UIColor?
  public var avatarSize: CGFloat = 30
  public var bubbleCornerRadius: CGFloat = 16
  public var messageHorizontalInset: CGFloat = 16
  public var messageVerticalInset: CGFloat = 6
  public var composerHeight: CGFloat = 56
  public var enabledActions: Set<PteIMUIAction> = [.image, .camera, .video, .location, .file, .redPacket, .gift, .order]
  public init() {}
  public static var `default`: PteIMUIChatStyle { PteIMUIChatStyle() }
}

/** Hosts can replace every image without subclassing a controller. */
public protocol PteIMUIIconProvider: AnyObject {
  func image(for key: PteIMUIIconKey, traitCollection: UITraitCollection) -> UIImage?
}

public enum PteIMUIIconKey: String, CaseIterable {
  case back, more, language, appearance, add, search, voice, keyboard, emoji, send
  case image, camera, video, location, file, redPacket, gift, order, chevron
}

public final class PteIMUISystemIconProvider: PteIMUIIconProvider {
  public init() {}
  public func image(for key: PteIMUIIconKey, traitCollection: UITraitCollection) -> UIImage? {
    let names: [PteIMUIIconKey: String] = [.back: "chevron.left", .more: "ellipsis", .language: "globe", .appearance: "moon", .add: "plus", .search: "magnifyingglass", .voice: "mic", .keyboard: "keyboard", .emoji: "face.smiling", .send: "paperplane.fill", .image: "photo", .camera: "camera", .video: "video", .location: "location", .file: "doc", .redPacket: "yensign.circle", .gift: "gift", .order: "bag", .chevron: "chevron.right"]
    return names[key].flatMap { UIImage(systemName: $0) }
  }
}

public enum PteIMUIConversationKind: Sendable { case single, group }

/** Host-owned display metadata; Core remains server-ID and message focused. */
public struct PteIMUIConversationPresentation {
  public var conversationId: String
  public var kind: PteIMUIConversationKind
  public var title: String
  public var subtitle: String?
  public var avatarText: String
  public var avatarImage: UIImage?
  public var unreadCount: Int
  public var updatedAt: Date?
  public init(conversationId: String, kind: PteIMUIConversationKind = .single, title: String, subtitle: String? = nil, avatarText: String = "", avatarImage: UIImage? = nil, unreadCount: Int = 0, updatedAt: Date? = nil) {
    self.conversationId = conversationId; self.kind = kind; self.title = title; self.subtitle = subtitle; self.avatarText = avatarText; self.avatarImage = avatarImage; self.unreadCount = unreadCount; self.updatedAt = updatedAt
  }
}

public struct PteIMUIContactPresentation {
  public var identifier: String
  public var kind: PteIMUIConversationKind
  public var title: String
  public var subtitle: String?
  public var avatarText: String
  public var avatarImage: UIImage?
  public init(identifier: String, kind: PteIMUIConversationKind = .single, title: String, subtitle: String? = nil, avatarText: String = "", avatarImage: UIImage? = nil) {
    self.identifier = identifier; self.kind = kind; self.title = title; self.subtitle = subtitle; self.avatarText = avatarText; self.avatarImage = avatarImage
  }
}
