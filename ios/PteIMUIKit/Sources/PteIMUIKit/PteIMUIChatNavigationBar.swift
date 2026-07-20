import UIKit

/**
 Fixed 44pt chat navigation row. Unlike `UINavigationBar`, it does not reserve
 symmetric space for title items, so a group avatar/title can follow the back
 control at the exact position used by the supplied chat screens.
 */
@MainActor public final class PteIMUIChatNavigationBar: UIView {
  public var onBack: (() -> Void)?
  public var onMore: (() -> Void)?
  /** Nil keeps the 36pt header avatar circular; set a value for host styling. */
  public var avatarCornerRadius: CGFloat? { didSet { applyAvatarShape() } }

  private let backButton = UIButton(type: .system)
  private let moreButton = UIButton(type: .system)
  private let avatar = UILabel()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let groupStack = UIStackView()
  private let singleStack = UIStackView()
  private var avatarLeading: NSLayoutConstraint!

  public override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
  }
  required init?(coder: NSCoder) { nil }

  public func configure(
    title: String?,
    subtitle: String?,
    avatarText: String?,
    avatarColor: UIColor?,
    palette: PteIMUIThemePalette,
    iconProvider: PteIMUIIconProvider,
    traitCollection: UITraitCollection
  ) {
    backgroundColor = palette.surfaceColor
    // Keep one-to-one and group conversations on the same Android-aligned
    // navigation structure: back, 36pt avatar, left-aligned copy, then more.
    // A one-to-one chat falls back to the peer's initial when no host avatar
    // has been supplied.
    let displayedAvatar = avatarText?.isEmpty == false ? avatarText : String((title ?? "?").prefix(1)).uppercased()
    avatar.isHidden = false
    groupStack.isHidden = false
    singleStack.isHidden = true
    avatar.text = displayedAvatar
    avatar.backgroundColor = avatarColor ?? UIColor(red: 0.00, green: 0.60, blue: 0.72, alpha: 1)
    titleLabel.text = title
    subtitleLabel.text = subtitle
    titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
    subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
    titleLabel.textColor = palette.primaryTextColor
    subtitleLabel.textColor = UIColor(red: 0.10, green: 0.76, blue: 0.45, alpha: 1)
    backButton.tintColor = palette.iconColor
    moreButton.tintColor = palette.iconColor
    // Navigation source cuts include transparent padding. Normalize the
    // canvas to the complete 44pt hit target so the visible glyph has the
    // same scale as the supplied second-level-page artwork.
    backButton.setImage(buttonFillingImage(iconProvider.image(for: .back, traitCollection: traitCollection)), for: .normal)
    moreButton.setImage(buttonFillingImage(iconProvider.image(for: .more, traitCollection: traitCollection)), for: .normal)
  }

  private func setup() {
    backgroundColor = .systemBackground
    [backButton, moreButton, avatar, titleLabel, subtitleLabel, groupStack, singleStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        [backButton, moreButton].forEach {
            $0.contentHorizontalAlignment = .fill
            $0.contentVerticalAlignment = .fill
            $0.imageView?.contentMode = .scaleAspectFit
        }
    backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
    avatar.textAlignment = .center; avatar.textColor = .white; avatar.font = .systemFont(ofSize: 17, weight: .bold); avatar.clipsToBounds = true; applyAvatarShape()
    titleLabel.font = .systemFont(ofSize: 17, weight: .bold); titleLabel.numberOfLines = 1
    subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium); subtitleLabel.numberOfLines = 1

    let groupCopy = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    groupCopy.axis = .vertical; groupCopy.alignment = .leading; groupCopy.spacing = 1
    groupStack.addArrangedSubview(avatar); groupStack.addArrangedSubview(groupCopy)
    groupStack.axis = .horizontal; groupStack.alignment = .center; groupStack.spacing = 12

    let singleTitle = UILabel(); let singleSubtitle = UILabel()
    // Labels are shared visually through their text mirrored below in
    // `configure`; the copies keep constraints independent between layouts.
    singleTitle.tag = 1; singleSubtitle.tag = 2
    singleTitle.font = .systemFont(ofSize: 17, weight: .bold); singleTitle.textAlignment = .center
    singleSubtitle.font = .systemFont(ofSize: 12, weight: .medium); singleSubtitle.textAlignment = .center
    singleStack.addArrangedSubview(singleTitle); singleStack.addArrangedSubview(singleSubtitle)
    singleStack.axis = .vertical; singleStack.alignment = .center; singleStack.spacing = 1

    addSubview(backButton); addSubview(moreButton); addSubview(groupStack); addSubview(singleStack)
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 44),
      backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), backButton.centerYAnchor.constraint(equalTo: centerYAnchor), backButton.widthAnchor.constraint(equalToConstant: 44), backButton.heightAnchor.constraint(equalToConstant: 44),
      moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), moreButton.centerYAnchor.constraint(equalTo: centerYAnchor), moreButton.widthAnchor.constraint(equalToConstant: 44), moreButton.heightAnchor.constraint(equalToConstant: 44),
      avatar.widthAnchor.constraint(equalToConstant: 36), avatar.heightAnchor.constraint(equalToConstant: 36),
      // Source layout: back control visual centre is x28; the 36pt group
      // avatar begins at x52 and the title begins at x100.
      groupStack.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2), groupStack.centerYAnchor.constraint(equalTo: centerYAnchor), groupStack.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -12),
      singleStack.centerXAnchor.constraint(equalTo: centerXAnchor), singleStack.centerYAnchor.constraint(equalTo: centerYAnchor), singleStack.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 12), singleStack.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -12)
    ])
  }

  public func setSingleCopy(title: String?, subtitle: String?, palette: PteIMUIThemePalette) {
    (singleStack.viewWithTag(1) as? UILabel)?.text = title
    (singleStack.viewWithTag(1) as? UILabel)?.textColor = palette.primaryTextColor
    (singleStack.viewWithTag(2) as? UILabel)?.text = subtitle
    (singleStack.viewWithTag(2) as? UILabel)?.textColor = palette.outgoingGradientStartColor
  }
  private func applyAvatarShape() { avatar.layer.cornerRadius = min(max(0, avatarCornerRadius ?? 18), 18) }
  private func buttonFillingImage(_ image: UIImage?) -> UIImage? {
    guard let image, let cgImage = image.cgImage else { return image }
    let scale = max(CGFloat(cgImage.width), CGFloat(cgImage.height)) / 44
    return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation).withRenderingMode(.alwaysTemplate)
  }
  @objc private func backTapped() { onBack?() }
  @objc private func moreTapped() { onMore?() }
}
