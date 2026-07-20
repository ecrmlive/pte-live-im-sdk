import UIKit
import PteIMSDK

/**
 A compact, UIKit-only message bubble. It deliberately renders every Core
 message type without reaching out to a remote image loader, so the host can
 attach its own media cache without making PteIMUIKit depend on a third party.
 */
open class PteIMUIMessageCell: UITableViewCell {
  public static let reuseIdentifier = "PteIMUIMessageCell"
  public var onAvatarTapped: (() -> Void)?
  public let avatar = UILabel()
  private let senderNameLabel = UILabel()
  private let bubble = PteIMUIGradientBubbleView()
  private let typeLabel = UILabel()
  private let bodyLabel = UILabel()
  private let reactionStack = UIStackView()
  private let stateLabel = UILabel()
  private var avatarLeading: NSLayoutConstraint!
  private var avatarTrailing: NSLayoutConstraint!
  private var bubbleLeading: NSLayoutConstraint!
  private var bubbleTrailing: NSLayoutConstraint!
  private var stateLeading: NSLayoutConstraint?
  private var stateTrailing: NSLayoutConstraint?
  private var reactionLeading: NSLayoutConstraint?
  private var reactionTrailing: NSLayoutConstraint?
  private var stateTopFromBubble: NSLayoutConstraint!
  private var stateTopFromReactions: NSLayoutConstraint!
  private var bubbleTop: NSLayoutConstraint!
  private var bubbleTopWithSenderName: NSLayoutConstraint!
  /// A multi-line UILabel has no stable intrinsic width during UITableView's
  /// estimated-height pass. Keep a concrete, content-derived bubble width so
  /// a reload cannot compress Chinese/English text into one character columns.
  private var bubbleContentWidth: NSLayoutConstraint!

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear

    avatar.textAlignment = .center
    avatar.font = .systemFont(ofSize: 12, weight: .bold)
    avatar.layer.cornerRadius = 17
    avatar.clipsToBounds = true
    avatar.isUserInteractionEnabled = true
    avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAvatar)))
    avatar.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(avatar)
    senderNameLabel.translatesAutoresizingMaskIntoConstraints = false
    senderNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
    senderNameLabel.numberOfLines = 1
    contentView.addSubview(senderNameLabel)

    bubble.layer.cornerRadius = 19
    bubble.clipsToBounds = true
    // Let the label's intrinsic content width define short text bubbles. The
    // per-direction boundary constraint added in configure() still caps long
    // messages and lets UILabel wrap naturally.
    bubble.setContentHuggingPriority(.required, for: .horizontal)
    bubble.setContentCompressionResistancePriority(.required, for: .horizontal)
    bubble.translatesAutoresizingMaskIntoConstraints = false
    bubble.outgoingGradient.startPoint = CGPoint(x: 0, y: 0)
    bubble.outgoingGradient.endPoint = CGPoint(x: 1, y: 1)
    contentView.addSubview(bubble)

    let stack = UIStackView(arrangedSubviews: [typeLabel, bodyLabel])
    stack.axis = .vertical
    stack.spacing = 4
    bubble.addSubview(stack)
    stateLabel.translatesAutoresizingMaskIntoConstraints = false
    reactionStack.axis = .horizontal; reactionStack.spacing = 5; reactionStack.alignment = .center; reactionStack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(reactionStack); contentView.addSubview(stateLabel)
    stack.translatesAutoresizingMaskIntoConstraints = false
    stateTopFromBubble = stateLabel.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 3)
    stateTopFromReactions = stateLabel.topAnchor.constraint(equalTo: reactionStack.bottomAnchor, constant: 3)
    bubbleTop = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5)
    bubbleTopWithSenderName = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 13),
      stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -13),
      stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -9),
      avatar.widthAnchor.constraint(equalToConstant: 34),
      avatar.heightAnchor.constraint(equalToConstant: 34),
      avatar.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 1),
      bubbleTop,
      senderNameLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
      senderNameLabel.bottomAnchor.constraint(equalTo: bubble.topAnchor, constant: -3),
      senderNameLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 5),
      reactionStack.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 4),
      stateTopFromBubble,
      stateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)
    ])
    bubbleContentWidth = bubble.widthAnchor.constraint(equalToConstant: 64)
    bubbleContentWidth.priority = .required
    bubbleContentWidth.isActive = true

    typeLabel.font = .preferredFont(forTextStyle: .caption1)
    typeLabel.adjustsFontForContentSizeCategory = true
    bodyLabel.font = .preferredFont(forTextStyle: .body)
    bodyLabel.numberOfLines = 0
    bodyLabel.adjustsFontForContentSizeCategory = true
    stateLabel.font = .preferredFont(forTextStyle: .caption2)
    stateLabel.adjustsFontForContentSizeCategory = true
  }
  required public init?(coder: NSCoder) { nil }

  public override func prepareForReuse() {
    super.prepareForReuse()
    typeLabel.isHidden = false
    bodyLabel.font = .preferredFont(forTextStyle: .body)
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
  }

  @objc private func tapAvatar() { onAvatarTapped?() }

  open func configure(message: PteIMMessage, outgoing: Bool, theme: PteIMUITheme, language: PteIMLanguage, style: PteIMUIChatStyle = .default, senderName: String? = nil, reactions: [PteIMUIReaction] = []) {
    let palette = theme.palette(for: traitCollection)
    let isEmoji = message.type == .emoji
    let isPlainText = message.type == .text

    typeLabel.text = isPlainText || isEmoji ? nil : PteIMUIMessageText.typeTitle(message.type, language: language)
    typeLabel.isHidden = typeLabel.text == nil
    bodyLabel.text = PteIMUIMessageText.render(message, language: language)
    bodyLabel.font = isEmoji ? .systemFont(ofSize: 31) : style.messageFont
    stateLabel.attributedText = PteIMUIMessageText.deliveryLine(for: message, outgoing: outgoing, language: language, color: outgoing ? (style.outgoingTextColor ?? palette.outgoingTextColor).withAlphaComponent(0.70) : (style.messageMetaColor ?? palette.secondaryTextColor))

    typeLabel.font = style.messageMetaFont
    stateLabel.font = style.messageMetaFont
    typeLabel.textColor = outgoing ? (style.outgoingTextColor ?? palette.outgoingTextColor).withAlphaComponent(0.82) : (style.messageMetaColor ?? palette.secondaryTextColor)
    bodyLabel.textColor = outgoing ? (style.outgoingTextColor ?? palette.outgoingTextColor) : (style.incomingTextColor ?? palette.incomingTextColor)
    stateLabel.textColor = outgoing ? (style.outgoingTextColor ?? palette.outgoingTextColor).withAlphaComponent(0.70) : (style.messageMetaColor ?? palette.secondaryTextColor)
    bubble.backgroundColor = outgoing ? .clear : (style.incomingBubbleColor ?? palette.incomingBubbleColor)
    bubble.layer.cornerRadius = style.bubbleCornerRadius
    updateBubbleContentWidth()
    bubble.outgoingGradient.isHidden = !outgoing
    // Cells are reused with different text widths. Clear any in-flight layer
    // animation before applying the new gradient so the background never
    // appears to expand horizontally when a conversation first opens.
    bubble.outgoingGradient.removeAllAnimations()
    bubble.outgoingGradient.colors = [palette.outgoingGradientStartColor.cgColor, palette.outgoingGradientEndColor.cgColor]
    senderNameLabel.text = senderName
    senderNameLabel.textColor = style.messageMetaColor ?? palette.secondaryTextColor
    senderNameLabel.isHidden = senderName?.isEmpty != false
    bubbleTop.isActive = senderNameLabel.isHidden
    bubbleTopWithSenderName.isActive = !senderNameLabel.isHidden

    let avatarSeed = message.senderId ?? "?"
    avatar.text = PteIMUIMessageText.avatarText(for: avatarSeed)
    avatar.textColor = outgoing ? .white : palette.outgoingGradientStartColor
    avatar.backgroundColor = outgoing ? palette.outgoingGradientEndColor : palette.surfaceColor
    avatar.font = .systemFont(ofSize: max(11, style.avatarSize * 0.36), weight: .bold)
    avatar.layer.cornerRadius = min(max(0, style.avatarCornerRadius ?? style.avatarSize / 2), style.avatarSize / 2)
    avatar.constraints.filter { $0.firstAttribute == .width }.first?.constant = style.avatarSize
    avatar.constraints.filter { $0.firstAttribute == .height }.first?.constant = style.avatarSize

    reactionStack.arrangedSubviews.forEach { reactionStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    reactions.filter { !$0.emoji.isEmpty && $0.count > 0 }.forEach { reaction in
      let pill = PteIMUIReactionPill(reaction: reaction, palette: palette)
      reactionStack.addArrangedSubview(pill)
    }
    let hasReactions = !reactionStack.arrangedSubviews.isEmpty
    reactionStack.isHidden = !hasReactions
    stateTopFromBubble.isActive = false
    stateTopFromReactions.isActive = false
    (hasReactions ? stateTopFromReactions : stateTopFromBubble).isActive = true

    [avatarLeading, avatarTrailing, bubbleLeading, bubbleTrailing, stateLeading, stateTrailing, reactionLeading, reactionTrailing].forEach { $0?.isActive = false }
    // Constraints are direction-specific. A reused outgoing cell may still
    // retain its trailing constraints when configured as incoming (and vice
    // versa); clear the references before activating the new direction.
    avatarLeading = nil; avatarTrailing = nil
    bubbleLeading = nil; bubbleTrailing = nil
    stateLeading = nil; stateTrailing = nil
    reactionLeading = nil; reactionTrailing = nil
    if outgoing {
      avatarTrailing = avatar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
      // This is a maximum-width boundary, not a fixed leading edge. A short
      // message therefore keeps only its text width plus bubble padding.
      bubbleLeading = bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 76)
      bubbleTrailing = bubble.trailingAnchor.constraint(equalTo: avatar.leadingAnchor, constant: -9)
      stateTrailing = stateLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor)
      reactionTrailing = reactionStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor)
    } else {
      avatarLeading = avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
      bubbleLeading = bubble.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 9)
      bubbleTrailing = bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -76)
      stateLeading = stateLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor)
      reactionLeading = reactionStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor)
    }
    [avatarLeading, avatarTrailing, bubbleLeading, bubbleTrailing, stateLeading, stateTrailing, reactionLeading, reactionTrailing].forEach { $0?.isActive = true }
  }

  private func updateBubbleContentWidth() {
    // UITableView can briefly assign a stale/oversized contentView width while
    // estimating rows after an insert. Use the stable screen width instead;
    // the directional constraints below still enforce the actual cell bounds.
    let containerWidth = UIScreen.main.bounds.width
    let maxBubbleWidth = max(120, containerWidth - 135)
    let maxTextWidth = maxBubbleWidth - 26
    let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    func width(for text: String?, font: UIFont, hidden: Bool) -> CGFloat {
      guard !hidden, let text, !text.isEmpty else { return 0 }
      return ceil((text as NSString).boundingRect(
        with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
        options: options,
        attributes: [.font: font],
        context: nil
      ).width)
    }

    let contentWidth = max(
      width(for: bodyLabel.text, font: bodyLabel.font, hidden: bodyLabel.isHidden),
      width(for: typeLabel.text, font: typeLabel.font, hidden: typeLabel.isHidden)
    )
    bubbleContentWidth.constant = min(maxBubbleWidth, max(54, contentWidth + 26))
    bodyLabel.preferredMaxLayoutWidth = maxTextWidth
    typeLabel.preferredMaxLayoutWidth = maxTextWidth
  }
}

private final class PteIMUIGradientBubbleView: UIView {
  let outgoingGradient = CAGradientLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    // CAGradientLayer animates bounds/position changes by default. A table
    // view may lay out a reused cell twice while it is entering the screen;
    // disable those implicit animations to keep the bubble background in sync
    // with its rounded UIKit container from the first frame.
    outgoingGradient.actions = [
      "bounds": NSNull(),
      "position": NSNull(),
      "cornerRadius": NSNull(),
      "colors": NSNull()
    ]
    layer.insertSublayer(outgoingGradient, at: 0)
  }

  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    outgoingGradient.frame = bounds
    outgoingGradient.cornerRadius = layer.cornerRadius
    CATransaction.commit()
  }
}

final class PteIMUIReactionPill: UILabel {
  init(reaction: PteIMUIReaction, palette: PteIMUIThemePalette) {
    super.init(frame: .zero)
    // A single reaction is represented by the emoji itself. The numerical
    // badge appears only when more than one participant reacted.
    text = reaction.count > 1 ? "\(reaction.emoji) \(reaction.count)" : reaction.emoji
    font = .systemFont(ofSize: 11, weight: .medium)
    textColor = palette.primaryTextColor
    textAlignment = .center
    backgroundColor = palette.surfaceColor
    layer.borderWidth = 1
    layer.borderColor = palette.dividerColor.cgColor
    layer.cornerRadius = 11
    clipsToBounds = true
    setContentHuggingPriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 22), widthAnchor.constraint(greaterThanOrEqualToConstant: 42)])
  }
  required init?(coder: NSCoder) { nil }
}

public enum PteIMUIMessageText {
  public static func typeName(_ type: PteIMMessageType, language: PteIMLanguage = .zhCN) -> String {
    switch type {
    case .text: return PteIMUILocalization.value("文本", "Text", language: language)
    case .emoji: return PteIMUILocalization.value("表情", "Emoji", language: language)
    case .image: return PteIMUILocalization.value("图片", "Image", language: language)
    case .video: return PteIMUILocalization.value("视频", "Video", language: language)
    case .voice: return PteIMUILocalization.value("语音", "Voice", language: language)
    case .location: return PteIMUILocalization.value("位置", "Location", language: language)
    case .gift: return PteIMUILocalization.value("礼物", "Gift", language: language)
    case .red_packet: return PteIMUILocalization.value("红包", "Red packet", language: language)
    case .order: return PteIMUILocalization.value("订单", "Order", language: language)
    case .file: return PteIMUILocalization.value("文件", "File", language: language)
    }
  }

  static func typeTitle(_ type: PteIMMessageType, language: PteIMLanguage) -> String {
    let symbol: String
    switch type {
    case .image: symbol = "▧"
    case .video: symbol = "▶"
    case .voice: symbol = "⌁"
    case .location: symbol = "⌖"
    case .gift: symbol = "✦"
    case .red_packet: symbol = "¥"
    case .order: symbol = "□"
    case .file: symbol = "▤"
    case .text, .emoji: symbol = ""
    }
    return "\(symbol)  \(typeName(type, language: language))"
  }

  public static func render(_ message: PteIMMessage, language: PteIMLanguage = .zhCN) -> String {
    if let text = message.text, !text.isEmpty { return text }
    if message.type == .emoji, let emoji = message.emojiId { return emojiGlyph(for: emoji) }
    if message.type == .image { return PteIMUILocalization.value("轻触查看图片", "Tap to view image", language: language) }
    if message.type == .video { return PteIMUILocalization.value("轻触播放视频", "Tap to play video", language: language) }
    if message.type == .file { return message.media?.fileName ?? PteIMUILocalization.value("文件", "File", language: language) }
    if let voice = message.voice { return "▁▃▆▃▁  \(max(1, voice.durationMs / 1000))\"" }
    if let location = message.location { return [location.name, location.address].compactMap { $0 }.joined(separator: "\n") }
    if let business = message.business { return [business.title, business.subtitle].compactMap { $0 }.joined(separator: "\n") }
    return message.contentJSON()
  }

  static func deliveryLine(for message: PteIMMessage, outgoing: Bool, language: PteIMLanguage, color: UIColor) -> NSAttributedString {
    let date = Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1000)
    let time = timeFormatter.string(from: date)
    guard outgoing else { return NSAttributedString(string: time, attributes: [.foregroundColor: color]) }
    switch message.state {
    case .sent, .pending, .uploading:
      let line = NSMutableAttributedString(string: time + "  ", attributes: [.foregroundColor: color])
      let resource = message.state == .sent ? "PteIMUIMessageRead" : "PteIMUIMessageUnread"
      if let image = UIImage(named: resource, in: .module, compatibleWith: nil), let cgImage = image.cgImage {
        let attachment = NSTextAttachment(); attachment.image = UIImage(cgImage: cgImage, scale: 3, orientation: image.imageOrientation); attachment.bounds = CGRect(x: 0, y: -1, width: 12, height: 12)
        line.append(NSAttributedString(attachment: attachment))
      }
      return line
    case .failed: return NSAttributedString(string: "\(time) · \(PteIMUILocalization.value("发送失败", "Failed", language: language))", attributes: [.foregroundColor: color])
    }
  }

  static func avatarText(for seed: String) -> String { String(seed.suffix(2)).uppercased() }
  static func emojiGlyph(for id: String) -> String {
    switch id {
    case "smile_001": return "☺︎"
    case "smile_002": return "✦"
    case "wave_001": return "◌"
    case "heart_001": return "♥"
    case "thumb_001": return "✓"
    default: return "✺"
    }
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
}
