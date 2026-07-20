import UIKit

/** A complete, replaceable visual skin for the three PteIMUIKit surfaces. */
@MainActor public final class PteIMUISkin {
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
@MainActor public final class PteIMUIListStyle {
  public var rowHeight: CGFloat = 73
  public var horizontalInset: CGFloat = 20
  public var avatarSize: CGFloat = 40
  /** Nil keeps the default circular avatar; set a value for a rounded square. */
  public var avatarCornerRadius: CGFloat?
  public var avatarFont: UIFont = .systemFont(ofSize: 14, weight: .bold)
  public var titleFont: UIFont = .systemFont(ofSize: 14, weight: .semibold)
  public var subtitleFont: UIFont = .systemFont(ofSize: 11, weight: .regular)
  public var timeFont: UIFont = .systemFont(ofSize: 10, weight: .regular)
  public var unreadFont: UIFont = .systemFont(ofSize: 11, weight: .bold)
  public var avatarTextColor: UIColor = .white
  public var titleColor: UIColor?
  public var subtitleColor: UIColor?
  public var timeColor: UIColor?
  public var unreadTextColor: UIColor = .white
  public var unreadBackgroundColor: UIColor?
  public var presenceOnlineColor: UIColor = UIColor(red: 0.16, green: 0.80, blue: 0.39, alpha: 1)
  public var presenceBorderColor: UIColor?
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
@MainActor public final class PteIMUIChatStyle {
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
  /** Nil keeps the default circular message avatar. */
  public var avatarCornerRadius: CGFloat?
  public var bubbleCornerRadius: CGFloat = 16
  public var messageHorizontalInset: CGFloat = 16
  public var messageVerticalInset: CGFloat = 6
  public var composerHeight: CGFloat = 56
  public var enabledActions: Set<PteIMUIAction> = [.image, .camera, .video, .location, .file, .redPacket, .gift, .order]
  public init() {}
  public static var `default`: PteIMUIChatStyle { PteIMUIChatStyle() }
}

/** Hosts can replace every image without subclassing a controller. */
@MainActor public protocol PteIMUIIconProvider: AnyObject {
  func image(for key: PteIMUIIconKey, traitCollection: UITraitCollection) -> UIImage?
}

public enum PteIMUIIconKey: String, CaseIterable {
  case brand, back, more, language, appearance, add, search, voice, keyboard, emoji, send
  case image, camera, video, location, file, redPacket, gift, order, chevron
  /// Contact-directory artwork from the supplied source cuts.
  case contactAddFriend, contactCreateGroup
  /// Input-bar-specific artwork; separate from navigation/action icons.
  case inputVoice, inputMore, inputEmoji, inputKeyboard, inputEmojiActive, inputMoreActive, inputClose
  /// More-panel artwork; separate from navigation/action icons.
  case panelImage, panelCamera, panelVideo, panelLocation, panelFile, panelRedPacket, panelGift, panelOrder
  /// Optional replacement artwork for built-in rich message cards.
  case messageImagePlaceholder, messageImagePreview, messageVideoPlay, messageRedPacketBackground, messageGiftBackground
}

@MainActor public final class PteIMUISystemIconProvider: PteIMUIIconProvider {
  public init() {}
  public func image(for key: PteIMUIIconKey, traitCollection: UITraitCollection) -> UIImage? {
    let light = traitCollection.userInterfaceStyle != .dark
    let resourceName: String?
    switch key {
    case .add: resourceName = light ? "PteIMUIConversationAddLight" : "PteIMUIConversationAddDark"
    case .back: resourceName = "PteIMUIBack"
    // The chat navigation artwork has only one supplied transparent source;
    // render it as a template so the same cut remains legible in both themes.
    case .more: resourceName = "PteIMUIChatMore"
    case .inputVoice: resourceName = light ? "PteIMUIInputVoiceLight" : "PteIMUIInputVoiceDark"
    case .inputMore: resourceName = light ? "PteIMUIInputMoreLight" : "PteIMUIInputMoreDark"
    case .inputEmoji: resourceName = light ? "PteIMUIInputEmojiLight" : "PteIMUIInputEmojiDark"
    case .inputKeyboard: resourceName = light ? "PteIMUIInputKeyboardLight" : "PteIMUIInputKeyboardDark"
    case .inputEmojiActive: resourceName = light ? "PteIMUIInputEmojiActiveLight" : "PteIMUIInputEmojiActiveDark"
    case .inputMoreActive: resourceName = light ? "PteIMUIInputMoreActiveLight" : "PteIMUIInputMoreActiveDark"
    case .inputClose: resourceName = light ? "PteIMUIInputCloseLight" : "PteIMUIInputCloseDark"
    case .panelImage: resourceName = "PteIMUIActionImage"
    case .panelCamera: resourceName = "PteIMUIActionCamera"
    case .panelVideo: resourceName = "PteIMUIActionVideo"
    case .panelLocation: resourceName = "PteIMUIActionLocation"
    case .panelRedPacket: resourceName = "PteIMUIActionRedPacket"
    case .panelOrder: resourceName = "PteIMUIActionOrder"
    case .panelFile: resourceName = "PteIMUIActionFile"
    case .contactAddFriend: resourceName = "PteIMUIContactAddFriend"
    case .contactCreateGroup: resourceName = "PteIMUIContactCreateGroup"
    case .chevron: resourceName = light ? "PteIMUIContactChevronLight" : "PteIMUIContactChevronDark"
    case .panelGift: resourceName = "PteIMUIActionGift"
    case .messageImagePreview: resourceName = "PteIMUIChatPreviewImage"
    case .messageVideoPlay: resourceName = "PteIMUIVideoPlay"
    case .messageRedPacketBackground: resourceName = "PteIMUIRedPacketBackground"
    case .messageGiftBackground: resourceName = "PteIMUIGiftBackground"
    default: resourceName = nil
    }
    if let resourceName, let image = UIImage(named: resourceName, in: .module, compatibleWith: traitCollection) {
      // Source cuts are supplied at @3x. SwiftPM resources do not preserve the
      // filename scale when renamed, so normalize it before UIKit uses the
      // image's intrinsic size in a button configuration.
      let normalized: UIImage
      if let cgImage = image.cgImage { normalized = UIImage(cgImage: cgImage, scale: 3, orientation: image.imageOrientation) }
      else { normalized = image }
      if key == .more || key == .back { return normalized.withRenderingMode(.alwaysTemplate) }
      return normalized.withRenderingMode(.alwaysOriginal)
    }
    let names: [PteIMUIIconKey: String] = [.back: "chevron.left", .more: "ellipsis", .language: "globe", .appearance: "moon", .add: "plus", .search: "magnifyingglass", .voice: "mic", .keyboard: "keyboard", .emoji: "face.smiling", .send: "paperplane.fill", .image: "photo", .camera: "camera", .video: "video", .location: "location", .file: "doc", .redPacket: "yensign.circle", .gift: "gift", .order: "bag", .chevron: "chevron.right", .contactAddFriend: "person.badge.plus", .contactCreateGroup: "person.3"]
    return names[key].flatMap { UIImage(systemName: $0) }
  }
}

/** Public access to packaged UIKit artwork for host-owned profile surfaces. */
@MainActor public enum PteIMUIResources {
  public static func image(named name: String, traitCollection: UITraitCollection? = nil) -> UIImage? {
    guard let image = UIImage(named: name, in: .module, compatibleWith: traitCollection) else { return nil }
    guard let cgImage = image.cgImage else { return image }
    // SwiftPM does not infer @3x when supplied artwork is renamed. All shipped
    // source cuts are @3x, so restore their intended UIKit point size here.
    return UIImage(cgImage: cgImage, scale: 3, orientation: image.imageOrientation)
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
  /** Optional host-owned avatar colour when no remote avatar image is supplied. */
  public var avatarBackgroundColor: UIColor?
  /** Host-owned presence state for the conversation list. */
  public var isOnline: Bool
  public var unreadCount: Int
  public var updatedAt: Date?
  public init(conversationId: String, kind: PteIMUIConversationKind = .single, title: String, subtitle: String? = nil, avatarText: String = "", avatarImage: UIImage? = nil, avatarBackgroundColor: UIColor? = nil, isOnline: Bool = false, unreadCount: Int = 0, updatedAt: Date? = nil) {
    self.conversationId = conversationId; self.kind = kind; self.title = title; self.subtitle = subtitle; self.avatarText = avatarText; self.avatarImage = avatarImage; self.avatarBackgroundColor = avatarBackgroundColor; self.isOnline = isOnline; self.unreadCount = unreadCount; self.updatedAt = updatedAt
  }
}

public struct PteIMUIContactPresentation {
  public var identifier: String
  public var kind: PteIMUIConversationKind
  public var title: String
  public var subtitle: String?
  public var avatarText: String
  public var avatarImage: UIImage?
  /** Optional host-owned avatar colour when no remote avatar image is supplied. */
  public var avatarBackgroundColor: UIColor?
  /** Optional UIKit section title, e.g. `PERSONAL` or `GROUPS`. */
  public var sectionTitle: String?
  /** Host-provided presence only; Core does not invent online state. */
  public var isOnline: Bool
  public init(identifier: String, kind: PteIMUIConversationKind = .single, title: String, subtitle: String? = nil, avatarText: String = "", avatarImage: UIImage? = nil, avatarBackgroundColor: UIColor? = nil, sectionTitle: String? = nil, isOnline: Bool = false) {
    self.identifier = identifier; self.kind = kind; self.title = title; self.subtitle = subtitle; self.avatarText = avatarText; self.avatarImage = avatarImage; self.avatarBackgroundColor = avatarBackgroundColor; self.sectionTitle = sectionTitle; self.isOnline = isOnline
  }
}
