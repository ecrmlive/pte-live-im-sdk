import UIKit
import PteIMSDK

/**
 Dedicated voice-message treatment. Voice must not reuse the generic text
 bubble: it has a fixed, compact waveform row with a microphone and duration.
 */
open class PteIMUIVoiceMessageCell: UITableViewCell {
  public static let reuseIdentifier = "PteIMUIVoiceMessageCell"
  public var onAvatarTapped: (() -> Void)?

  private let avatar = UILabel()
  private let senderNameLabel = UILabel()
  private let bubble = UIView()
  private let microphone = UIImageView()
  private let waveform = UIImageView()
  private let durationLabel = UILabel()
  private let reactionStack = UIStackView()
  private let stateLabel = UILabel()
  private let incomingGradient = CAGradientLayer()
  private let outgoingGradient = CAGradientLayer()
  private var avatarLeading: NSLayoutConstraint?
  private var avatarTrailing: NSLayoutConstraint?
  private var bubbleLeading: NSLayoutConstraint?
  private var bubbleTrailing: NSLayoutConstraint?
  private var stateLeading: NSLayoutConstraint?
  private var stateTrailing: NSLayoutConstraint?
  private var reactionLeading: NSLayoutConstraint?
  private var reactionTrailing: NSLayoutConstraint?
  private var stateTopFromBubble: NSLayoutConstraint!
  private var stateTopFromReactions: NSLayoutConstraint!
  private var bubbleWidth: NSLayoutConstraint!
  private var bubbleTop: NSLayoutConstraint!
  private var bubbleTopWithSenderName: NSLayoutConstraint!
  private var avatarWidth: NSLayoutConstraint!
  private var avatarHeight: NSLayoutConstraint!

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear

    avatar.translatesAutoresizingMaskIntoConstraints = false
    avatar.textAlignment = .center
    avatar.font = .systemFont(ofSize: 12, weight: .bold)
    avatar.layer.cornerRadius = 17
    avatar.clipsToBounds = true
    avatar.isUserInteractionEnabled = true
    avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAvatar)))

    senderNameLabel.translatesAutoresizingMaskIntoConstraints = false
    senderNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
    senderNameLabel.numberOfLines = 1

    bubble.translatesAutoresizingMaskIntoConstraints = false
    bubble.layer.cornerRadius = 22
    bubble.clipsToBounds = true
    incomingGradient.startPoint = CGPoint(x: 0, y: 0)
    incomingGradient.endPoint = CGPoint(x: 1, y: 1)
    outgoingGradient.startPoint = CGPoint(x: 0, y: 0)
    outgoingGradient.endPoint = CGPoint(x: 1, y: 1)
    bubble.layer.insertSublayer(incomingGradient, at: 0)
    bubble.layer.insertSublayer(outgoingGradient, at: 0)

    [microphone, waveform, durationLabel, reactionStack, stateLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    microphone.contentMode = .scaleAspectFit
    waveform.contentMode = .scaleAspectFit
    durationLabel.font = .systemFont(ofSize: 12, weight: .medium)
    stateLabel.font = .systemFont(ofSize: 11, weight: .regular)
    reactionStack.axis = .horizontal
    reactionStack.spacing = 5
    reactionStack.alignment = .center

    contentView.addSubview(avatar)
    contentView.addSubview(senderNameLabel)
    contentView.addSubview(bubble)
    bubble.addSubview(microphone)
    bubble.addSubview(waveform)
    bubble.addSubview(durationLabel)
    contentView.addSubview(reactionStack)
    contentView.addSubview(stateLabel)

    bubbleWidth = bubble.widthAnchor.constraint(equalToConstant: 173)
    bubbleTop = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5)
    bubbleTopWithSenderName = bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22)
    avatarWidth = avatar.widthAnchor.constraint(equalToConstant: 34)
    avatarHeight = avatar.heightAnchor.constraint(equalToConstant: 34)
    stateTopFromBubble = stateLabel.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 3)
    stateTopFromReactions = stateLabel.topAnchor.constraint(equalTo: reactionStack.bottomAnchor, constant: 3)
    NSLayoutConstraint.activate([
      avatarWidth,
      avatarHeight,
      avatar.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 1),
      bubbleTop,
      bubble.heightAnchor.constraint(equalToConstant: 44),
      bubbleWidth,
      senderNameLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
      senderNameLabel.bottomAnchor.constraint(equalTo: bubble.topAnchor, constant: -3),
      senderNameLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 5),
      microphone.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 16),
      microphone.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
      microphone.widthAnchor.constraint(equalToConstant: 16),
      microphone.heightAnchor.constraint(equalToConstant: 16),
      waveform.leadingAnchor.constraint(equalTo: microphone.trailingAnchor, constant: 12),
      waveform.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
      waveform.widthAnchor.constraint(equalToConstant: 78),
      waveform.heightAnchor.constraint(equalToConstant: 20),
      durationLabel.leadingAnchor.constraint(equalTo: waveform.trailingAnchor, constant: 12),
      durationLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -16),
      durationLabel.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
      reactionStack.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 4),
      stateTopFromBubble,
      stateLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)
    ])
  }

  required public init?(coder: NSCoder) { nil }

  public override func layoutSubviews() {
    super.layoutSubviews()
    incomingGradient.frame = bubble.bounds
    outgoingGradient.frame = bubble.bounds
  }

  @objc private func tapAvatar() { onAvatarTapped?() }

  open func configure(message: PteIMMessage, outgoing: Bool, theme: PteIMUITheme, language: PteIMLanguage, style: PteIMUIChatStyle = .default, senderName: String? = nil, reactions: [PteIMUIReaction] = []) {
    let palette = theme.palette(for: traitCollection)
    let duration = max(1, Int((message.voice?.durationMs ?? 1_000) / 1_000))
    // Voice content has a fixed 173 × 44 design surface. The waveform and
    // duration stay stable regardless of the recording length.
    bubbleWidth.constant = 173
    durationLabel.text = language == .zhCN ? "\(duration)秒" : "\(duration)s"

    let seed = message.senderId ?? "?"
    avatar.text = PteIMUIMessageText.avatarText(for: seed)
    avatar.font = .systemFont(ofSize: max(11, style.avatarSize * 0.36), weight: .bold)
    avatar.textColor = outgoing ? .white : palette.outgoingGradientStartColor
    avatar.backgroundColor = outgoing ? palette.outgoingGradientEndColor : palette.surfaceColor
    avatar.layer.cornerRadius = style.avatarSize / 2
    avatarWidth.constant = style.avatarSize
    avatarHeight.constant = style.avatarSize

    senderNameLabel.text = senderName
    senderNameLabel.textColor = style.messageMetaColor ?? palette.secondaryTextColor
    senderNameLabel.isHidden = senderName?.isEmpty != false
    bubbleTop.isActive = senderNameLabel.isHidden
    bubbleTopWithSenderName.isActive = !senderNameLabel.isHidden

    let isDark = traitCollection.userInterfaceStyle == .dark
    incomingGradient.isHidden = outgoing || !isDark
    incomingGradient.colors = [
      UIColor(red: 166 / 255, green: 132 / 255, blue: 255 / 255, alpha: 0.06).cgColor,
      UIColor(red: 173 / 255, green: 70 / 255, blue: 255 / 255, alpha: 0.04).cgColor,
      UIColor(red: 0 / 255, green: 211 / 255, blue: 243 / 255, alpha: 0.05).cgColor
    ]
    incomingGradient.locations = [0, 0.5, 1]
    outgoingGradient.isHidden = !outgoing
    outgoingGradient.colors = [palette.outgoingGradientStartColor.cgColor, palette.outgoingGradientEndColor.cgColor]
    bubble.backgroundColor = outgoing ? .clear : (isDark ? .clear : .white)
    bubble.layer.borderWidth = outgoing ? 0 : 1
    bubble.layer.borderColor = outgoing ? UIColor.clear.cgColor : palette.outgoingGradientStartColor.withAlphaComponent(0.36).cgColor
    let assetPrefix = isDark ? "PteIMUIVoiceDark" : "PteIMUIVoiceLight"
    let direction = outgoing ? "Outgoing" : "Incoming"
    let microphoneAsset = UIImage(named: "\(assetPrefix)\(direction)Icon", in: .module, compatibleWith: traitCollection)
    let waveformAsset = UIImage(named: "\(assetPrefix)\(direction)Wave", in: .module, compatibleWith: traitCollection)
    // The dark outgoing source cut is a purple alpha mask. On the purple
    // outgoing bubble the reference renders that exact shape in white.
    if outgoing && isDark {
      microphone.image = microphoneAsset?.withRenderingMode(.alwaysTemplate)
      waveform.image = waveformAsset?.withRenderingMode(.alwaysTemplate)
      microphone.tintColor = style.outgoingTextColor ?? palette.outgoingTextColor
      waveform.tintColor = style.outgoingTextColor ?? palette.outgoingTextColor
    } else {
      microphone.image = microphoneAsset
      waveform.image = waveformAsset
      microphone.tintColor = nil
      waveform.tintColor = nil
    }
    durationLabel.textColor = outgoing ? (style.outgoingTextColor ?? palette.outgoingTextColor) : (style.messageMetaColor ?? palette.secondaryTextColor)
    stateLabel.attributedText = PteIMUIMessageText.deliveryLine(for: message, outgoing: outgoing, language: language, color: outgoing ? (style.outgoingTextColor ?? palette.outgoingTextColor).withAlphaComponent(0.70) : (style.messageMetaColor ?? palette.secondaryTextColor))

    reactionStack.arrangedSubviews.forEach { reactionStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    reactions.filter { !$0.emoji.isEmpty && $0.count > 0 }.forEach {
      reactionStack.addArrangedSubview(PteIMUIReactionPill(reaction: $0, palette: palette))
    }
    let hasReactions = !reactionStack.arrangedSubviews.isEmpty
    reactionStack.isHidden = !hasReactions
    stateTopFromBubble.isActive = false
    stateTopFromReactions.isActive = false
    (hasReactions ? stateTopFromReactions : stateTopFromBubble).isActive = true

    [avatarLeading, avatarTrailing, bubbleLeading, bubbleTrailing, stateLeading, stateTrailing, reactionLeading, reactionTrailing].forEach { $0?.isActive = false }
    // UITableView reuses this cell for both directions; never reactivate the
    // old side's anchor alongside the new one.
    avatarLeading = nil; avatarTrailing = nil
    bubbleLeading = nil; bubbleTrailing = nil
    stateLeading = nil; stateTrailing = nil
    reactionLeading = nil; reactionTrailing = nil
    if outgoing {
      avatarTrailing = avatar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
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
}
