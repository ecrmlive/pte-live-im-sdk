import UIKit
import PteLiveIM

public final class PteIMUIMessageCell: UITableViewCell {
  public static let reuseIdentifier = "PteIMUIMessageCell"
  private let bubble = UIView()
  private let typeLabel = UILabel()
  private let bodyLabel = UILabel()
  private let stateLabel = UILabel()
  private var leading: NSLayoutConstraint!
  private var trailing: NSLayoutConstraint!

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear
    contentView.addSubview(bubble)
    bubble.layer.cornerRadius = 14
    bubble.translatesAutoresizingMaskIntoConstraints = false
    leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
    trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -72)
    NSLayoutConstraint.activate([bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5), bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5), leading, trailing])
    let stack = UIStackView(arrangedSubviews: [typeLabel, bodyLabel, stateLabel])
    stack.axis = .vertical; stack.spacing = 4
    bubble.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9), stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -9)])
    typeLabel.font = .preferredFont(forTextStyle: .caption1); typeLabel.adjustsFontForContentSizeCategory = true
    bodyLabel.font = .preferredFont(forTextStyle: .body); bodyLabel.numberOfLines = 0; bodyLabel.adjustsFontForContentSizeCategory = true
    stateLabel.font = .preferredFont(forTextStyle: .caption2); stateLabel.adjustsFontForContentSizeCategory = true
  }
  required init?(coder: NSCoder) { nil }

  public func configure(message: PteIMMessage, outgoing: Bool, theme: PteIMUITheme, language: PteIMLanguage) {
    let content = PteIMUIMessageText.render(message)
    typeLabel.text = PteIMUIMessageText.typeName(message.type, language: language)
    bodyLabel.text = content
    stateLabel.text = message.state.rawValue
    typeLabel.textColor = theme.secondaryTextColor; bodyLabel.textColor = theme.primaryTextColor; stateLabel.textColor = theme.secondaryTextColor
    bubble.backgroundColor = outgoing ? theme.outgoingBubbleColor : theme.incomingBubbleColor
    leading.isActive = false; trailing.isActive = false
    if outgoing { trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16); leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 72) }
    else { leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16); trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -72) }
    leading.isActive = true; trailing.isActive = true
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
  public static func render(_ message: PteIMMessage) -> String {
    if let text = message.text, !text.isEmpty { return text }
    if let emoji = message.emojiId { return "\(message.packageId ?? "default")/\(emoji)" }
    if let media = message.media { return media.url ?? "媒体" }
    if let voice = message.voice { return "\(voice.durationMs) ms" }
    if let location = message.location { return [location.name, location.address].compactMap { $0 }.joined(separator: " · ") }
    if let business = message.business { return [business.title, business.subtitle].compactMap { $0 }.joined(separator: " · ") }
    return message.contentJSON()
  }
}
