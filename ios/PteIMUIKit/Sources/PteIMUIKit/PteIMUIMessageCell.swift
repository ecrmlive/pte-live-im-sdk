import UIKit
import PteIMSDK

/**
 A compact, UIKit-only message bubble. It deliberately renders every Core
 message type without reaching out to a remote image loader, so the host can
 attach its own media cache without making PteIMUIkit depend on a third party.
 */
public final class PteIMUIMessageCell: UITableViewCell {
  public static let reuseIdentifier = "PteIMUIMessageCell"
  private let avatar = UILabel()
  private let bubble = UIView()
  private let typeLabel = UILabel()
  private let bodyLabel = UILabel()
  private let stateLabel = UILabel()
  private let outgoingGradient = CAGradientLayer()
  private var avatarLeading: NSLayoutConstraint!
  private var avatarTrailing: NSLayoutConstraint!
  private var bubbleLeading: NSLayoutConstraint!
  private var bubbleTrailing: NSLayoutConstraint!

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear

    avatar.textAlignment = .center
    avatar.font = .systemFont(ofSize: 12, weight: .bold)
    avatar.layer.cornerRadius = 17
    avatar.clipsToBounds = true
    avatar.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(avatar)

    bubble.layer.cornerRadius = 19
    bubble.clipsToBounds = true
    bubble.translatesAutoresizingMaskIntoConstraints = false
    outgoingGradient.startPoint = CGPoint(x: 0, y: 0)
    outgoingGradient.endPoint = CGPoint(x: 1, y: 1)
    bubble.layer.insertSublayer(outgoingGradient, at: 0)
    contentView.addSubview(bubble)

    let stack = UIStackView(arrangedSubviews: [typeLabel, bodyLabel, stateLabel])
    stack.axis = .vertical
    stack.spacing = 4
    bubble.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 13),
      stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -13),
      stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -7),
      avatar.widthAnchor.constraint(equalToConstant: 34),
      avatar.heightAnchor.constraint(equalToConstant: 34),
      avatar.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 1),
      bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
      bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)
    ])

    typeLabel.font = .preferredFont(forTextStyle: .caption1)
    typeLabel.adjustsFontForContentSizeCategory = true
    bodyLabel.font = .preferredFont(forTextStyle: .body)
    bodyLabel.numberOfLines = 0
    bodyLabel.adjustsFontForContentSizeCategory = true
    stateLabel.font = .preferredFont(forTextStyle: .caption2)
    stateLabel.adjustsFontForContentSizeCategory = true
  }
  required init?(coder: NSCoder) { nil }

  public override func prepareForReuse() {
    super.prepareForReuse()
    typeLabel.isHidden = false
    bodyLabel.font = .preferredFont(forTextStyle: .body)
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    outgoingGradient.frame = bubble.bounds
  }

  public func configure(message: PteIMMessage, outgoing: Bool, theme: PteIMUITheme, language: PteIMLanguage) {
    let palette = theme.palette(for: traitCollection)
    let isEmoji = message.type == .emoji
    let isPlainText = message.type == .text

    typeLabel.text = isPlainText || isEmoji ? nil : PteIMUIMessageText.typeTitle(message.type, language: language)
    typeLabel.isHidden = typeLabel.text == nil
    bodyLabel.text = PteIMUIMessageText.render(message, language: language)
    bodyLabel.font = isEmoji ? .systemFont(ofSize: 31) : .preferredFont(forTextStyle: .body)
    stateLabel.text = PteIMUIMessageText.deliveryLine(for: message, outgoing: outgoing, language: language)

    typeLabel.textColor = outgoing ? palette.outgoingTextColor.withAlphaComponent(0.82) : palette.secondaryTextColor
    bodyLabel.textColor = outgoing ? palette.outgoingTextColor : palette.incomingTextColor
    stateLabel.textColor = outgoing ? palette.outgoingTextColor.withAlphaComponent(0.70) : palette.secondaryTextColor
    bubble.backgroundColor = outgoing ? .clear : palette.incomingBubbleColor
    outgoingGradient.isHidden = !outgoing
    outgoingGradient.colors = [palette.outgoingGradientStartColor.cgColor, palette.outgoingGradientEndColor.cgColor]

    let avatarSeed = message.senderId ?? "?"
    avatar.text = PteIMUIMessageText.avatarText(for: avatarSeed)
    avatar.textColor = outgoing ? .white : palette.outgoingGradientStartColor
    avatar.backgroundColor = outgoing ? palette.outgoingGradientEndColor : palette.surfaceColor

    [avatarLeading, avatarTrailing, bubbleLeading, bubbleTrailing].forEach { $0?.isActive = false }
    if outgoing {
      avatarTrailing = avatar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
      bubbleLeading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 76)
      bubbleTrailing = bubble.trailingAnchor.constraint(equalTo: avatar.leadingAnchor, constant: -9)
    } else {
      avatarLeading = avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
      bubbleLeading = bubble.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 9)
      bubbleTrailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -76)
    }
    [avatarLeading, avatarTrailing, bubbleLeading, bubbleTrailing].forEach { $0?.isActive = true }
  }
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
    case .text, .emoji: symbol = ""
    }
    return "\(symbol)  \(typeName(type, language: language))"
  }

  public static func render(_ message: PteIMMessage, language: PteIMLanguage = .zhCN) -> String {
    if let text = message.text, !text.isEmpty { return text }
    if message.type == .emoji, let emoji = message.emojiId { return emojiGlyph(for: emoji) }
    if message.type == .image { return PteIMUILocalization.value("轻触查看图片", "Tap to view image", language: language) }
    if message.type == .video { return PteIMUILocalization.value("轻触播放视频", "Tap to play video", language: language) }
    if let voice = message.voice { return "▁▃▆▃▁  \(max(1, voice.durationMs / 1000))\"" }
    if let location = message.location { return [location.name, location.address].compactMap { $0 }.joined(separator: "\n") }
    if let business = message.business { return [business.title, business.subtitle].compactMap { $0 }.joined(separator: "\n") }
    return message.contentJSON()
  }

  static func deliveryLine(for message: PteIMMessage, outgoing: Bool, language: PteIMLanguage) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1000)
    let time = timeFormatter.string(from: date)
    guard outgoing else { return time }
    switch message.state {
    case .sent: return time
    case .pending, .uploading: return "\(time) · \(PteIMUILocalization.value("发送中", "Sending", language: language))"
    case .failed: return "\(time) · \(PteIMUILocalization.value("发送失败", "Failed", language: language))"
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
