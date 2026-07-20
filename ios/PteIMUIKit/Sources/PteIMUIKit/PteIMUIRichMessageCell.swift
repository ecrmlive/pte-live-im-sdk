import UIKit
import MapKit
import PteIMSDK

/**
 UIKit-owned presentations for media and business messages. The Core payload
 remains generic; this cell only decides how it is displayed. Hosts can still
 replace the cell through `messageCellReuseIdentifier(for:)`.
 */
open class PteIMUIRichMessageCell: UITableViewCell {
  public static let reuseIdentifier = "PteIMUIRichMessageCell"
  public var onAvatarTapped: (() -> Void)?
  private let avatar = UILabel()
  private let senderNameLabel = UILabel()
  private let card = UIView()
  private let imagePlaceholderGradient = CAGradientLayer()
  private let artwork = UIImageView()
  private let icon = UIImageView()
  private let videoPlayButton = UIView()
  private let videoPlayIcon = UIImageView()
  private let videoDurationBadge = UIView()
  private let videoDurationIcon = UIImageView()
  private let videoDurationLabel = UILabel()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let footerLabel = UILabel()
  private let footerLeadingDecoration = UIImageView()
  private let footerTrailingDecoration = UIImageView()
  private let reactionStack = UIStackView()
  private let timeLabel = UILabel()
  private var avatarLeading: NSLayoutConstraint?
  private var avatarTrailing: NSLayoutConstraint?
  private var cardLeading: NSLayoutConstraint?
  private var cardTrailing: NSLayoutConstraint?
  private var timeLeading: NSLayoutConstraint?
  private var timeTrailing: NSLayoutConstraint?
  private var reactionLeading: NSLayoutConstraint?
  private var reactionTrailing: NSLayoutConstraint?
  private var timeTopFromCard: NSLayoutConstraint!
  private var timeTopFromReactions: NSLayoutConstraint!
  private var cardWidth: NSLayoutConstraint!
  private var cardHeight: NSLayoutConstraint!
  private var cardTop: NSLayoutConstraint!
  private var cardTopWithSenderName: NSLayoutConstraint!
  private var standardContentConstraints: [NSLayoutConstraint] = []
  private var businessContentConstraints: [NSLayoutConstraint] = []
  private var imageContentConstraints: [NSLayoutConstraint] = []
  private var videoContentConstraints: [NSLayoutConstraint] = []
  private var fullArtworkConstraints: [NSLayoutConstraint] = []
  private var locationArtworkConstraints: [NSLayoutConstraint] = []
  private var locationContentConstraints: [NSLayoutConstraint] = []
  private var artworkTask: URLSessionDataTask?
  private var representedMessageId: String?

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none; backgroundColor = .clear
    avatar.textAlignment = .center; avatar.layer.cornerRadius = 17; avatar.clipsToBounds = true; avatar.isUserInteractionEnabled = true
    avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAvatar)))
    card.layer.cornerRadius = 16; card.clipsToBounds = true
    imagePlaceholderGradient.startPoint = CGPoint(x: 0, y: 1)
    imagePlaceholderGradient.endPoint = CGPoint(x: 1, y: 0)
    card.layer.insertSublayer(imagePlaceholderGradient, at: 0)
    artwork.contentMode = .scaleAspectFill; artwork.clipsToBounds = true
    icon.contentMode = .scaleAspectFit
    videoPlayButton.layer.cornerRadius = 23
    videoPlayButton.layer.borderWidth = 1
    videoPlayButton.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
    videoPlayButton.backgroundColor = UIColor.white.withAlphaComponent(0.10)
    videoPlayButton.isHidden = true
    videoPlayIcon.contentMode = .scaleAspectFit
    videoDurationBadge.backgroundColor = UIColor.white.withAlphaComponent(0.10)
    videoDurationBadge.layer.cornerRadius = 12
    videoDurationBadge.clipsToBounds = true
    videoDurationBadge.isHidden = true
    videoDurationIcon.contentMode = .scaleAspectFit
    videoDurationIcon.isHidden = true
    videoDurationLabel.font = .systemFont(ofSize: 12, weight: .medium)
    videoDurationLabel.textColor = .white
    videoDurationLabel.isHidden = true
    [footerLeadingDecoration, footerTrailingDecoration].forEach {
      $0.image = UIImage(named: "PteIMUIBusinessStar", in: .module, compatibleWith: traitCollection)
      $0.contentMode = .scaleAspectFit
      $0.isHidden = true
    }
    titleLabel.numberOfLines = 2; titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    subtitleLabel.numberOfLines = 2; subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
    footerLabel.font = .systemFont(ofSize: 11, weight: .medium)
    timeLabel.font = .systemFont(ofSize: 11, weight: .regular)
    reactionStack.axis = .horizontal; reactionStack.spacing = 5; reactionStack.alignment = .center
    senderNameLabel.font = .systemFont(ofSize: 11, weight: .medium); senderNameLabel.numberOfLines = 1
    [avatar, senderNameLabel, card, artwork, icon, videoPlayButton, videoPlayIcon, videoDurationBadge, videoDurationIcon, videoDurationLabel, titleLabel, subtitleLabel, footerLabel, footerLeadingDecoration, footerTrailingDecoration, reactionStack, timeLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    contentView.addSubview(avatar); contentView.addSubview(senderNameLabel); contentView.addSubview(card); card.addSubview(artwork); card.addSubview(icon); card.addSubview(videoPlayButton); videoPlayButton.addSubview(videoPlayIcon); card.addSubview(videoDurationBadge); videoDurationBadge.addSubview(videoDurationIcon); videoDurationBadge.addSubview(videoDurationLabel); card.addSubview(titleLabel); card.addSubview(subtitleLabel); card.addSubview(footerLabel); card.addSubview(footerLeadingDecoration); card.addSubview(footerTrailingDecoration); contentView.addSubview(reactionStack); contentView.addSubview(timeLabel)
    cardWidth = card.widthAnchor.constraint(equalToConstant: 220)
    cardHeight = card.heightAnchor.constraint(equalToConstant: 112)
    let standardIconLeading = icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16)
    let standardIconTop = icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 16)
    let standardTitleLeading = titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10)
    let standardTitleTrailing = titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14)
    let standardTitleTop = titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 15)
    let standardSubtitleLeading = subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor)
    let standardSubtitleTrailing = subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor)
    let standardSubtitleTop = subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
    let standardFooterLeading = footerLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16)
    let standardFooterTrailing = footerLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
    let standardFooterBottom = footerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
    standardContentConstraints = [standardIconLeading, standardIconTop, standardTitleLeading, standardTitleTrailing, standardTitleTop, standardSubtitleLeading, standardSubtitleTrailing, standardSubtitleTop, standardFooterLeading, standardFooterTrailing, standardFooterBottom]
    businessContentConstraints = [
      titleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      // The artwork already contains the gift/red-packet icon. Align copy to
      // its lower edge without vertically stretching the original artwork.
      titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 90),
      titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 18),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -18),
      subtitleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
      subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 18),
      subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -18),
      footerLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      footerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15),
      footerLeadingDecoration.trailingAnchor.constraint(equalTo: footerLabel.leadingAnchor, constant: -9),
      footerLeadingDecoration.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
      footerLeadingDecoration.widthAnchor.constraint(equalToConstant: 12),
      footerLeadingDecoration.heightAnchor.constraint(equalTo: footerLeadingDecoration.widthAnchor),
      footerTrailingDecoration.leadingAnchor.constraint(equalTo: footerLabel.trailingAnchor, constant: 9),
      footerTrailingDecoration.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
      footerTrailingDecoration.widthAnchor.constraint(equalToConstant: 12),
      footerTrailingDecoration.heightAnchor.constraint(equalTo: footerTrailingDecoration.widthAnchor)
    ]
    imageContentConstraints = [
      icon.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 53),
      titleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      titleLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 7),
      titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 14),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14)
    ]
    videoContentConstraints = [
      videoPlayButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      videoPlayButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      videoPlayButton.widthAnchor.constraint(equalToConstant: 46),
      videoPlayButton.heightAnchor.constraint(equalTo: videoPlayButton.widthAnchor),
      videoPlayIcon.centerXAnchor.constraint(equalTo: videoPlayButton.centerXAnchor),
      videoPlayIcon.centerYAnchor.constraint(equalTo: videoPlayButton.centerYAnchor),
      videoPlayIcon.widthAnchor.constraint(equalToConstant: 20),
      videoPlayIcon.heightAnchor.constraint(equalTo: videoPlayIcon.widthAnchor),
      videoDurationBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
      videoDurationBadge.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
      videoDurationBadge.widthAnchor.constraint(equalToConstant: 72),
      videoDurationBadge.heightAnchor.constraint(equalToConstant: 24),
      videoDurationIcon.leadingAnchor.constraint(equalTo: videoDurationBadge.leadingAnchor, constant: 6),
      videoDurationIcon.centerYAnchor.constraint(equalTo: videoDurationBadge.centerYAnchor),
      videoDurationIcon.widthAnchor.constraint(equalToConstant: 12),
      videoDurationIcon.heightAnchor.constraint(equalTo: videoDurationIcon.widthAnchor),
      videoDurationLabel.leadingAnchor.constraint(equalTo: videoDurationIcon.trailingAnchor, constant: 4),
      videoDurationLabel.trailingAnchor.constraint(equalTo: videoDurationBadge.trailingAnchor, constant: -6),
      videoDurationLabel.centerYAnchor.constraint(equalTo: videoDurationBadge.centerYAnchor)
    ]
    fullArtworkConstraints = [
      artwork.leadingAnchor.constraint(equalTo: card.leadingAnchor), artwork.trailingAnchor.constraint(equalTo: card.trailingAnchor), artwork.topAnchor.constraint(equalTo: card.topAnchor), artwork.bottomAnchor.constraint(equalTo: card.bottomAnchor)
    ]
    locationArtworkConstraints = [
      artwork.leadingAnchor.constraint(equalTo: card.leadingAnchor), artwork.trailingAnchor.constraint(equalTo: card.trailingAnchor), artwork.topAnchor.constraint(equalTo: card.topAnchor), artwork.heightAnchor.constraint(equalToConstant: 96)
    ]
    locationContentConstraints = [
      titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
      titleLabel.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 7),
      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
    ]
    timeTopFromCard = timeLabel.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 3)
    timeTopFromReactions = timeLabel.topAnchor.constraint(equalTo: reactionStack.bottomAnchor, constant: 3)
    cardTop = card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5)
    cardTopWithSenderName = card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22)
    NSLayoutConstraint.activate([
      avatar.widthAnchor.constraint(equalToConstant: 34), avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor), avatar.topAnchor.constraint(equalTo: card.topAnchor),
      cardTop, cardWidth, cardHeight,
      senderNameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor), senderNameLabel.bottomAnchor.constraint(equalTo: card.topAnchor, constant: -3), senderNameLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 5),
      reactionStack.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 4),
      timeTopFromCard, timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
      icon.widthAnchor.constraint(equalToConstant: 30), icon.heightAnchor.constraint(equalTo: icon.widthAnchor)
    ])
    NSLayoutConstraint.activate(standardContentConstraints)
    NSLayoutConstraint.activate(fullArtworkConstraints)
  }
  required public init?(coder: NSCoder) { nil }
  public override func prepareForReuse() {
    super.prepareForReuse()
    artworkTask?.cancel(); artworkTask = nil; representedMessageId = nil
    artwork.image = nil; artwork.backgroundColor = .clear
  }
  public override func layoutSubviews() {
    super.layoutSubviews()
    imagePlaceholderGradient.frame = card.bounds
    imagePlaceholderGradient.cornerRadius = card.layer.cornerRadius
  }
  @objc private func tapAvatar() { onAvatarTapped?() }

  private func applySharedCardGradient(isDark: Bool) {
    imagePlaceholderGradient.isHidden = false
    imagePlaceholderGradient.colors = isDark ? [
      UIColor(red: 166 / 255, green: 132 / 255, blue: 255 / 255, alpha: 0.06).cgColor,
      UIColor(red: 173 / 255, green: 70 / 255, blue: 255 / 255, alpha: 0.04).cgColor,
      UIColor(red: 0 / 255, green: 211 / 255, blue: 243 / 255, alpha: 0.05).cgColor
    ] : [
      UIColor(red: 29 / 255, green: 41 / 255, blue: 61 / 255, alpha: 0.50).cgColor,
      UIColor(red: 15 / 255, green: 23 / 255, blue: 43 / 255, alpha: 0.50).cgColor,
      UIColor(white: 0, alpha: 0.50).cgColor
    ]
    imagePlaceholderGradient.locations = [0, 0.5, 1]
  }

  open func configure(message: PteIMMessage, outgoing: Bool, theme: PteIMUITheme, language: PteIMLanguage, style: PteIMUIChatStyle, senderName: String? = nil, iconProvider: PteIMUIIconProvider? = nil, reactions: [PteIMUIReaction] = []) {
    let palette = theme.palette(for: traitCollection)
    let isDark = traitCollection.userInterfaceStyle == .dark
    senderNameLabel.text = senderName
    senderNameLabel.textColor = palette.secondaryTextColor
    senderNameLabel.isHidden = senderName?.isEmpty != false
    cardTop.isActive = senderNameLabel.isHidden
    cardTopWithSenderName.isActive = !senderNameLabel.isHidden
    let seed = message.senderId ?? "?"
    avatar.text = PteIMUIMessageText.avatarText(for: seed); avatar.font = .systemFont(ofSize: max(11, style.avatarSize * 0.36), weight: .bold)
    avatar.textColor = outgoing ? .white : palette.outgoingGradientStartColor; avatar.backgroundColor = outgoing ? palette.outgoingGradientEndColor : palette.surfaceColor
    avatar.layer.cornerRadius = min(max(0, style.avatarCornerRadius ?? style.avatarSize / 2), style.avatarSize / 2)
    avatar.constraints.filter { $0.firstAttribute == .width }.first?.constant = style.avatarSize
    representedMessageId = message.clientMsgId
    artworkTask?.cancel(); artworkTask = nil
    artwork.isHidden = true; artwork.image = nil; icon.isHidden = false; videoPlayButton.isHidden = true; videoDurationBadge.isHidden = true; videoDurationIcon.isHidden = true; videoDurationLabel.isHidden = true; titleLabel.isHidden = false; footerLabel.isHidden = false; footerLeadingDecoration.isHidden = true; footerTrailingDecoration.isHidden = true; imagePlaceholderGradient.isHidden = true
    // Cells may be reused after an Auto Layout conflict from a prior rich
    // message. Reassert the fixed design-card dimensions before choosing the
    // next message presentation.
    cardWidth.isActive = true; cardHeight.isActive = true
    cardWidth.constant = 220
    NSLayoutConstraint.deactivate(businessContentConstraints + imageContentConstraints + videoContentConstraints + locationArtworkConstraints + locationContentConstraints)
    NSLayoutConstraint.activate(standardContentConstraints)
    NSLayoutConstraint.activate(fullArtworkConstraints)
    titleLabel.textAlignment = .natural; subtitleLabel.textAlignment = .natural; footerLabel.textAlignment = .natural
    titleLabel.numberOfLines = 2; subtitleLabel.numberOfLines = 2
    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold); subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular); footerLabel.font = .systemFont(ofSize: 11, weight: .medium)
    card.backgroundColor = palette.incomingBubbleColor; titleLabel.textColor = palette.incomingTextColor; subtitleLabel.textColor = palette.secondaryTextColor; footerLabel.textColor = palette.secondaryTextColor
    let timeColor = outgoing ? palette.outgoingGradientEndColor : palette.secondaryTextColor
    timeLabel.attributedText = PteIMUIMessageText.deliveryLine(for: message, outgoing: outgoing, language: language, color: timeColor)
    timeLabel.textColor = timeColor
    reactionStack.arrangedSubviews.forEach { reactionStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    reactions.filter { !$0.emoji.isEmpty && $0.count > 0 }.forEach { reactionStack.addArrangedSubview(PteIMUIReactionPill(reaction: $0, palette: palette)) }
    let hasReactions = !reactionStack.arrangedSubviews.isEmpty
    reactionStack.isHidden = !hasReactions
    timeTopFromCard.isActive = false
    timeTopFromReactions.isActive = false
    (hasReactions ? timeTopFromReactions : timeTopFromCard).isActive = true

    switch message.type {
    case .red_packet, .gift:
      NSLayoutConstraint.deactivate(standardContentConstraints)
      NSLayoutConstraint.activate(businessContentConstraints)
      artwork.isHidden = false; icon.isHidden = true
      // Preserve the supplied cut asset's native height so the title/subtitle
      // share the same vertical landmarks as the design source.
      cardHeight.constant = message.type == .red_packet ? 186 : 182
      artwork.image = iconProvider?.image(for: message.type == .red_packet ? .messageRedPacketBackground : .messageGiftBackground, traitCollection: traitCollection) ?? UIImage(named: message.type == .red_packet ? "PteIMUIRedPacketBackground" : "PteIMUIGiftBackground", in: .module, compatibleWith: traitCollection)
      titleLabel.text = message.business?.title; subtitleLabel.text = message.business?.subtitle
      titleLabel.textAlignment = .center; subtitleLabel.textAlignment = .center; footerLabel.textAlignment = .center
      titleLabel.font = .systemFont(ofSize: 15, weight: .bold); subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium); footerLabel.font = .systemFont(ofSize: 12, weight: .bold)
      titleLabel.textColor = UIColor(red: 1, green: 0.89, blue: 0.34, alpha: 1); subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.86)
      let actionTitle = message.type == .red_packet ? PteIMUILocalization.value("查看红包", "Open red packet", language: language) : PteIMUILocalization.value("查看礼物", "View gift", language: language)
      footerLabel.text = actionTitle
      footerLabel.textColor = UIColor.white.withAlphaComponent(0.88)
      footerLeadingDecoration.isHidden = false; footerTrailingDecoration.isHidden = false
    case .image, .video:
      NSLayoutConstraint.deactivate(standardContentConstraints)
      cardHeight.constant = message.type == .image ? 176 : 136
      cardWidth.constant = message.type == .image ? 176 : 208
      artwork.isHidden = false; icon.isHidden = false
      artwork.image = nil
      card.backgroundColor = .clear
      applySharedCardGradient(isDark: isDark)
      if message.type == .video {
        NSLayoutConstraint.activate(videoContentConstraints)
        artwork.backgroundColor = .clear
        icon.isHidden = true
        videoPlayButton.isHidden = false
        videoDurationBadge.isHidden = false
        videoDurationIcon.isHidden = false
        videoDurationLabel.isHidden = false
        videoPlayIcon.image = iconProvider?.image(for: .messageVideoPlay, traitCollection: traitCollection) ?? PteIMUIResources.image(named: "PteIMUIVideoPlay", traitCollection: traitCollection)
        videoDurationIcon.image = PteIMUIResources.image(named: "PteIMUIVideoDuration", traitCollection: traitCollection)
        titleLabel.text = nil; subtitleLabel.text = nil
        footerLabel.isHidden = true
        videoDurationLabel.text = Self.videoDurationText(milliseconds: message.media?.durationMs)
      } else {
        NSLayoutConstraint.activate(imageContentConstraints)
        let previewImage = iconProvider?.image(for: .messageImagePreview, traitCollection: traitCollection)
        artwork.backgroundColor = .clear; artwork.image = previewImage
        icon.image = iconProvider?.image(for: .messageImagePlaceholder, traitCollection: traitCollection) ?? UIImage(named: "PteIMUIImageIcon", in: .module, compatibleWith: traitCollection)
        icon.tintColor = .white; icon.isHidden = previewImage != nil
        titleLabel.text = previewImage == nil ? PteIMUILocalization.value("Photo · 图片", "Photo · Image", language: language) : nil
        subtitleLabel.text = nil; footerLabel.text = nil
        titleLabel.textAlignment = .center; titleLabel.textColor = .white; titleLabel.isHidden = previewImage != nil
      }
      loadRemoteArtwork(url: message.type == .video ? (message.media?.coverUrl ?? message.media?.thumbnailUrl ?? message.media?.url) : (message.media?.thumbnailUrl ?? message.media?.url), messageId: message.clientMsgId)
    case .location:
      NSLayoutConstraint.deactivate(standardContentConstraints + fullArtworkConstraints)
      NSLayoutConstraint.activate(locationArtworkConstraints + locationContentConstraints)
      cardWidth.constant = 208; cardHeight.constant = 148; artwork.isHidden = false; artwork.backgroundColor = .clear; icon.isHidden = true; footerLabel.isHidden = true
      titleLabel.text = message.location?.name; subtitleLabel.text = message.location?.address
      titleLabel.numberOfLines = 1; subtitleLabel.numberOfLines = 1
      titleLabel.font = .systemFont(ofSize: 12, weight: .semibold); subtitleLabel.font = .systemFont(ofSize: 10, weight: .regular)
      titleLabel.textColor = palette.primaryTextColor; subtitleLabel.textColor = palette.secondaryTextColor
      loadMapArtwork(location: message.location, messageId: message.clientMsgId)
    case .order:
      cardHeight.constant = 118
      card.backgroundColor = isDark ? .clear : .white
      if isDark { applySharedCardGradient(isDark: true) }
      icon.image = UIImage(systemName: "shippingbox.fill"); icon.tintColor = palette.outgoingGradientStartColor
      titleLabel.text = message.business?.title; subtitleLabel.text = message.business?.subtitle
      footerLabel.text = PteIMUILocalization.value("订单 · 查看详情", "Order · View details", language: language)
    case .file:
      // File cards keep metadata together beneath the filename. The prior
      // footer repeated the size a second time and created the marked extra
      // blank line in the supplied comparison.
      // File metadata is a two-line compact card. Keep a small lower inset
      // instead of reserving a hidden footer row.
      cardHeight.constant = 66
      icon.image = PteIMUIResources.image(named: "PteIMUIMessageFile", traitCollection: traitCollection) ?? UIImage(systemName: "doc.fill")
      icon.tintColor = palette.outgoingGradientStartColor
      titleLabel.text = message.media?.fileName ?? PteIMUILocalization.value("文件", "File", language: language)
      let size = message.media?.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
      let rawKind = message.media?.mimeType ?? "FILE"
      // Demo payloads may already contain a display string such as
      // “PDF · 2.4 MB”; retain only its type before appending the byte size.
      let kind = rawKind.components(separatedBy: "/").first?
        .components(separatedBy: "·").first?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased() ?? "FILE"
      subtitleLabel.text = size.isEmpty ? kind : "\(kind) · \(size)"
      footerLabel.text = nil; footerLabel.isHidden = true
    default:
      cardHeight.constant = 108; titleLabel.text = PteIMUIMessageText.render(message, language: language); subtitleLabel.text = nil; footerLabel.text = nil
    }

    [avatarLeading, avatarTrailing, cardLeading, cardTrailing, timeLeading, timeTrailing, reactionLeading, reactionTrailing].forEach { $0?.isActive = false }
    // Do not reactivate constraints from the opposite direction when this
    // rich-media cell is reused by UITableView.
    avatarLeading = nil; avatarTrailing = nil
    cardLeading = nil; cardTrailing = nil
    timeLeading = nil; timeTrailing = nil
    reactionLeading = nil; reactionTrailing = nil
    if outgoing {
      // Rich cards have an explicit design width. Pinning both sides forces
      // UIKit to stretch their artwork across the whole timeline.
      avatarTrailing = avatar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16); cardTrailing = card.trailingAnchor.constraint(equalTo: avatar.leadingAnchor, constant: -9); cardTrailing?.priority = .defaultHigh; timeTrailing = timeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor); reactionTrailing = reactionStack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
    } else {
      avatarLeading = avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16); cardLeading = card.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 9); cardLeading?.priority = .defaultHigh; timeLeading = timeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor); reactionLeading = reactionStack.leadingAnchor.constraint(equalTo: card.leadingAnchor)
    }
    [avatarLeading, avatarTrailing, cardLeading, cardTrailing, timeLeading, timeTrailing, reactionLeading, reactionTrailing].forEach { $0?.isActive = true }
  }

  private static func videoDurationText(milliseconds: Int64?) -> String {
    let totalSeconds = max(Int64(0), (milliseconds ?? 0) / 1_000)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private func loadRemoteArtwork(url: String?, messageId: String) {
    guard let url, let resource = URL(string: url), resource.scheme == "https" else { return }
    artworkTask = URLSession.shared.dataTask(with: resource) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard self?.representedMessageId == messageId else { return }
        self?.artwork.image = image
      }
    }
    artworkTask?.resume()
  }

  private func loadMapArtwork(location: PteIMLocation?, messageId: String) {
    guard let location else { return }
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude), latitudinalMeters: 1_200, longitudinalMeters: 1_200)
    options.size = CGSize(width: 220, height: 156)
    options.mapType = .standard
    MKMapSnapshotter(options: options).start(with: .main) { [weak self] snapshot, _ in
      let image = snapshot?.image
      Task { @MainActor [weak self] in
        guard self?.representedMessageId == messageId else { return }
        self?.artwork.image = image
      }
    }
  }
}
