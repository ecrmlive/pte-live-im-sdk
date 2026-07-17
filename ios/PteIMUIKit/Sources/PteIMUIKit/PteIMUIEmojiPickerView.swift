import UIKit
import PteIMSDK

/** Switches the picker between a host-curated common set and the complete
 bundled/custom catalogue. */
public enum PteIMUIEmojiScope: Sendable { case common, all }

/** An externally supplied raster expression. It is rendered inside a 44×44pt
 cell with a 24×32pt image envelope, matching the chat source design. */
public struct PteIMUICustomEmojiImage {
  public let id: String
  public let image: UIImage
  public init(id: String, image: UIImage) { self.id = id; self.image = image }
}

/**
 A pageless, scrollable Unicode emoji picker. It deliberately stores the
 Unicode sequence as `emojiId`, so selected emoji have identical identifiers
 in Chinese and English and can be sent directly by PteIMSDK.
 */
open class PteIMUIEmojiPickerView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  public var onSelect: ((PteIMUIEmojiItem) -> Void)?
  public var onBackspace: (() -> Void)?
  public var onSend: (() -> Void)?
  public var skin: PteIMUISkin { didSet { applySkin() } }
  public var language: PteIMLanguage = .zhCN { didSet { applyCopy(); categoryControl.reloadData(); collectionView.reloadData() } }
  public var selectedCategory: PteIMUIEmojiCategory = .smileysAndEmotion { didSet { refreshItems(); collectionView.setContentOffset(.zero, animated: false) } }
  /** The actual selected expression is highlighted; switching a category never
   changes the attachment button state. */
  public var selectedEmojiID: String? { didSet { collectionView.reloadData() } }
  /** Host-supplied entries participate in the “all” collection and retain the
   required 44pt cells / 24×32pt artwork envelope. */
  public var customEmojiItems: [PteIMUIEmojiItem] = [] { didSet { refreshItems() } }
  public var commonEmojiItems: [PteIMUIEmojiItem] = [] { didSet { refreshItems() } }
  public var customImageEmojiItems: [PteIMUICustomEmojiImage] = [] { didSet { refreshItems() } }
  public var scope: PteIMUIEmojiScope = .all { didSet { refreshItems(); categoryControl.reloadData() } }

  private let categoryControl: UICollectionView
  private let collectionView: UICollectionView
  private let sectionTitleLabel = UILabel()
  private let categoryDivider = UIView()
  private let backspaceButton = UIButton(type: .system)
  private let sendButton = UIButton(type: .system)
  /// Space occupied by the two bottom-right floating controls plus their gap
  /// from the safe area. The grid scrolls above this reserved region.
  private let bottomActionReservation: CGFloat = 56
  private var items = PteIMUIEmojiCatalog.items(in: .smileysAndEmotion)
  private var imageItems: [String: UIImage] = [:]
  // Matches HarmonyOS exactly: history plus these nine fixed popular emoji.
  private let hotEmojiIDs = ["😀", "👋", "❤", "🐶", "🍎", "⚽", "🚗", "💡", "🎉"]
  // 热门表情只是固定快捷入口，初始状态不预选任何一个，避免第二个
  // 表情带有非设计稿要求的选中背景。
  private var selectedHotEmojiIndex: Int?
  private var historyEmojiItems: [PteIMUIEmojiItem] = []
  private static let categoryReuse = "PteIMUIEmojiCategoryCell"
  private static let emojiReuse = "PteIMUIEmojiCell"

  public init(skin: PteIMUISkin = .default) {
    self.skin = skin
    let categoryLayout = UICollectionViewFlowLayout()
    categoryLayout.scrollDirection = .horizontal
    // History plus nine fixed 36pt controls fits the iPhone row without
    // scrolling: 10 × 36pt items separated by 1pt.
    categoryLayout.minimumInteritemSpacing = 1
    categoryLayout.minimumLineSpacing = 1
    categoryLayout.sectionInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
    categoryControl = UICollectionView(frame: .zero, collectionViewLayout: categoryLayout)
    // A fixed grid avoids UICollectionViewFlowLayout's automatic spacing
    // distribution. The design calls for exact 44×44 tiles.
    collectionView = UICollectionView(frame: .zero, collectionViewLayout: PteIMUIFixedEmojiGridLayout())
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    [categoryControl, collectionView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; $0.backgroundColor = .clear; $0.dataSource = self; $0.delegate = self; addSubview($0) }
    // The delete/send actions float above the lower-right corner. Reserve
    // scrollable content below the final emoji row so no cell is obscured or
    // loses its tap target, matching the Android input panel behavior.
    collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomActionReservation, right: 0)
    collectionView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomActionReservation, right: 0)
    // Header is a fixed history action plus nine fixed popular expressions. It
    // intentionally never scrolls or changes order between launches.
    categoryControl.isScrollEnabled = false
    sectionTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    sectionTitleLabel.font = .systemFont(ofSize: 13, weight: .bold)
    categoryDivider.translatesAutoresizingMaskIntoConstraints = false
    addSubview(categoryDivider)
    addSubview(sectionTitleLabel)
    categoryControl.register(PteIMUIEmojiPickerCell.self, forCellWithReuseIdentifier: Self.categoryReuse)
    collectionView.register(PteIMUIEmojiPickerCell.self, forCellWithReuseIdentifier: Self.emojiReuse)
    NSLayoutConstraint.activate([
      // Match the grid gutter so the history button centre sits on the first
      // emoji column, rather than 4pt to its left.
      categoryControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), categoryControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), categoryControl.topAnchor.constraint(equalTo: topAnchor), categoryControl.heightAnchor.constraint(equalToConstant: 44),
      categoryDivider.leadingAnchor.constraint(equalTo: leadingAnchor), categoryDivider.trailingAnchor.constraint(equalTo: trailingAnchor), categoryDivider.topAnchor.constraint(equalTo: categoryControl.bottomAnchor), categoryDivider.heightAnchor.constraint(equalToConstant: 1),
      sectionTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), sectionTitleLabel.topAnchor.constraint(equalTo: categoryDivider.bottomAnchor, constant: 4), sectionTitleLabel.heightAnchor.constraint(equalToConstant: 18),
      // Keep the design's blank horizontal gutter while allowing the grid to
      // continue under the floating actions at the bottom-right.
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), collectionView.topAnchor.constraint(equalTo: sectionTitleLabel.bottomAnchor, constant: 3), collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    [backspaceButton, sendButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
    backspaceButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
    sendButton.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
    backspaceButton.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
    sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    NSLayoutConstraint.activate([
      // The grid reaches the physical screen edge, while actions stay 5pt
      // above the lower safe area so the Home Indicator never covers them.
      sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), sendButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -5), sendButton.widthAnchor.constraint(equalToConstant: 44), sendButton.heightAnchor.constraint(equalToConstant: 44),
      backspaceButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -12), backspaceButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor), backspaceButton.widthAnchor.constraint(equalToConstant: 44), backspaceButton.heightAnchor.constraint(equalToConstant: 44)
    ])
    applyCopy()
    applySkin()
  }
  required public init?(coder: NSCoder) { nil }

  private func applySkin() {
    let palette = skin.theme.palette(for: traitCollection)
    backgroundColor = palette.panelColor
    sectionTitleLabel.textColor = palette.secondaryTextColor
    categoryDivider.backgroundColor = palette.dividerColor
    [backspaceButton, sendButton].forEach { $0.tintColor = palette.iconColor; $0.backgroundColor = palette.surfaceColor; $0.layer.cornerRadius = 14 }
    sendButton.backgroundColor = palette.outgoingGradientStartColor
    sendButton.tintColor = .white
    collectionView.reloadData(); categoryControl.reloadData()
  }
  private func applyCopy() {
    sectionTitleLabel.text = PteIMUILocalization.value("表情", "SMILEYS", language: language)
  }
  open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) { super.traitCollectionDidChange(previousTraitCollection); applySkin() }
  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { collectionView === categoryControl ? hotEmojiIDs.count + 1 : items.count }
  public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    if collectionView === categoryControl {
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.categoryReuse, for: indexPath) as! PteIMUIEmojiPickerCell
      if indexPath.item == 0 {
        let icon = UIImage(named: "PteIMUIEmojiHistory", in: .module, compatibleWith: traitCollection)
        // The supplied history artwork fills its complete 36×32pt control.
        cell.configure(title: "", image: icon, imageSize: CGSize(width: 36, height: 32), selected: scope == .common, skin: skin)
        cell.accessibilityLabel = PteIMUILocalization.value("历史使用", "Emoji history", language: language)
      } else {
        let emoji = hotEmojiIDs[indexPath.item - 1]
        // Preserve the native emoji aspect ratio for popular expressions.
        cell.configure(title: emoji, selected: scope == .all && selectedHotEmojiIndex == indexPath.item, skin: skin)
        cell.accessibilityLabel = PteIMUILocalization.value("热门表情", "Popular emoji", language: language)
      }
      return cell
    }
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.emojiReuse, for: indexPath) as! PteIMUIEmojiPickerCell
    let item = items[indexPath.item]
    cell.configure(title: item.id, image: imageItems[item.id], selected: item.id == selectedEmojiID, skin: skin)
    return cell
  }
  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    if collectionView === categoryControl {
      if indexPath.item == 0 {
        // History is a toggle, not a one-way filter: tapping it again returns
        // immediately to the default complete emoji catalogue.
        if scope == .common {
          scope = .all
        } else {
          selectedHotEmojiIndex = nil
          scope = .common
        }
      } else {
        selectedHotEmojiIndex = indexPath.item
        scope = .all
        let item = PteIMUIEmojiItem(id: hotEmojiIDs[indexPath.item - 1], category: .smileysAndEmotion)
        selectedEmojiID = item.id
        recordHistory(item)
        onSelect?(item)
      }
      categoryControl.reloadData()
    }
    else {
      let item = items[indexPath.item]
      selectedEmojiID = item.id
      recordHistory(item)
      onSelect?(item)
    }
  }
  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    if collectionView === categoryControl { return CGSize(width: 36, height: 32) }
    return CGSize(width: 44, height: 44)
  }
  @objc private func backspaceTapped() { onBackspace?() }
  @objc private func sendTapped() { onSend?() }
  private func refreshItems() {
    imageItems = Dictionary(uniqueKeysWithValues: customImageEmojiItems.map { ($0.id, $0.image) })
    let baseline: [PteIMUIEmojiItem]
    switch scope {
    case .common:
      baseline = historyEmojiItems.isEmpty ? commonEmojiItems : historyEmojiItems
    case .all:
      baseline = PteIMUIEmojiCatalog.items(in: selectedCategory) + customEmojiItems
    }
    let images = customImageEmojiItems.map { PteIMUIEmojiItem(id: $0.id, category: selectedCategory) }
    items = baseline + images
    collectionView.reloadData()
  }
  private func recordHistory(_ item: PteIMUIEmojiItem) {
    historyEmojiItems.removeAll { $0.id == item.id }
    historyEmojiItems.insert(item, at: 0)
    if historyEmojiItems.count > 48 { historyEmojiItems.removeLast(historyEmojiItems.count - 48) }
  }
}

/**
 A deterministic eight-column emoji grid. Flow layout expands inter-item
 spacing to consume spare width on some device sizes, which makes 44pt emoji
 cells drift from the supplied design. This layout never adds column gaps.
 */
private final class PteIMUIFixedEmojiGridLayout: UICollectionViewLayout {
  private let itemSide: CGFloat = 44
  // A 338pt picker must show six full 44pt rows after its fixed header.
  // Keep the supplied 44×44 tiles contiguous vertically so no blank band is
  // left above the physical bottom edge.
  private let lineSpacing: CGFloat = 0
  private let columns = 8
  private var attributes: [UICollectionViewLayoutAttributes] = []
  private var cachedBounds: CGSize = .zero

  override func prepare() {
    guard let collectionView else { return }
    let bounds = collectionView.bounds.size
    let count = collectionView.numberOfItems(inSection: 0)
    guard bounds != cachedBounds || attributes.count != count else { return }
    cachedBounds = bounds
    attributes = (0..<count).map { index in
      let row = index / columns
      let column = index % columns
      let indexPath = IndexPath(item: index, section: 0)
      let item = UICollectionViewLayoutAttributes(forCellWith: indexPath)
      item.frame = CGRect(
        x: CGFloat(column) * itemSide,
        y: CGFloat(row) * (itemSide + lineSpacing),
        width: itemSide,
        height: itemSide
      )
      return item
    }
  }

  override var collectionViewContentSize: CGSize {
    guard let collectionView else { return .zero }
    let rows = Int(ceil(Double(collectionView.numberOfItems(inSection: 0)) / Double(columns)))
    let height = rows == 0 ? 0 : CGFloat(rows) * itemSide + CGFloat(rows - 1) * lineSpacing
    return CGSize(width: collectionView.bounds.width, height: height)
  }

  override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    attributes.filter { $0.frame.intersects(rect) }
  }

  override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
  }

  override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
    newBounds.size != cachedBounds
  }
}

private final class PteIMUIEmojiPickerCell: UICollectionViewCell {
  private let label = UILabel()
  private let imageView = UIImageView()
  private var imageWidth: NSLayoutConstraint!
  private var imageHeight: NSLayoutConstraint!
  override init(frame: CGRect) {
    super.init(frame: frame)
    label.translatesAutoresizingMaskIntoConstraints = false; label.textAlignment = .center
    imageView.translatesAutoresizingMaskIntoConstraints = false; imageView.contentMode = .scaleAspectFit
    contentView.addSubview(label); contentView.addSubview(imageView)
    imageWidth = imageView.widthAnchor.constraint(equalToConstant: 24)
    imageHeight = imageView.heightAnchor.constraint(equalToConstant: 32)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), label.topAnchor.constraint(equalTo: contentView.topAnchor), label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor), imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), imageWidth, imageHeight
    ])
  }
  required init?(coder: NSCoder) { nil }
  func configure(title: String, image: UIImage? = nil, imageSize: CGSize = CGSize(width: 24, height: 32), fontSize: CGFloat? = nil, selected: Bool, skin: PteIMUISkin) {
    let palette = skin.theme.palette(for: traitCollection)
    label.text = title
    label.isHidden = image != nil
    imageView.image = image
    imageView.isHidden = image == nil
    imageWidth.constant = imageSize.width
    imageHeight.constant = imageSize.height
    imageView.tintColor = selected ? palette.outgoingGradientStartColor : palette.iconColor
    label.font = .systemFont(ofSize: fontSize ?? (title.count <= 2 ? 26 : 11), weight: title.count <= 2 ? .regular : .medium)
    label.transform = .identity
    label.textColor = selected ? palette.outgoingGradientStartColor : palette.primaryTextColor
    // Expression selection is intentionally local to the 44×44 emoji cell.
    // It never changes the bottom “+” action or the panel mode.
    contentView.backgroundColor = selected ? palette.outgoingGradientStartColor.withAlphaComponent(0.18) : .clear
    contentView.layer.cornerRadius = 14
  }
}
