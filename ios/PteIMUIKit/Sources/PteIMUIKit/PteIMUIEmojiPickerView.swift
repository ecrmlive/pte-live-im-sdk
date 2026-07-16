import UIKit
import PteIMSDK

/**
 A pageless, scrollable Unicode emoji picker. It deliberately stores the
 Unicode sequence as `emojiId`, so selected emoji have identical identifiers
 in Chinese and English and can be sent directly by PteIMSDK.
 */
open class PteIMUIEmojiPickerView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  public var onSelect: ((PteIMUIEmojiItem) -> Void)?
  public var skin: PteIMUISkin { didSet { applySkin() } }
  public var language: PteIMLanguage = .zhCN { didSet { categoryControl.reloadData(); collectionView.reloadData() } }
  public var selectedCategory: PteIMUIEmojiCategory = .smileysAndEmotion { didSet { items = PteIMUIEmojiCatalog.items(in: selectedCategory); collectionView.reloadData(); collectionView.setContentOffset(.zero, animated: false) } }

  private let categoryControl: UICollectionView
  private let collectionView: UICollectionView
  private var items = PteIMUIEmojiCatalog.items(in: .smileysAndEmotion)
  private static let categoryReuse = "PteIMUIEmojiCategoryCell"
  private static let emojiReuse = "PteIMUIEmojiCell"

  public init(skin: PteIMUISkin = .default) {
    self.skin = skin
    let categoryLayout = UICollectionViewFlowLayout(); categoryLayout.scrollDirection = .horizontal; categoryLayout.minimumInteritemSpacing = 6
    categoryControl = UICollectionView(frame: .zero, collectionViewLayout: categoryLayout)
    let emojiLayout = UICollectionViewFlowLayout(); emojiLayout.minimumInteritemSpacing = 2; emojiLayout.minimumLineSpacing = 4
    collectionView = UICollectionView(frame: .zero, collectionViewLayout: emojiLayout)
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    [categoryControl, collectionView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; $0.backgroundColor = .clear; $0.dataSource = self; $0.delegate = self; addSubview($0) }
    categoryControl.register(PteIMUIEmojiPickerCell.self, forCellWithReuseIdentifier: Self.categoryReuse)
    collectionView.register(PteIMUIEmojiPickerCell.self, forCellWithReuseIdentifier: Self.emojiReuse)
    NSLayoutConstraint.activate([
      categoryControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), categoryControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), categoryControl.topAnchor.constraint(equalTo: topAnchor), categoryControl.heightAnchor.constraint(equalToConstant: 30),
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), collectionView.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 4), collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    applySkin()
  }
  required public init?(coder: NSCoder) { nil }

  private func applySkin() { backgroundColor = skin.theme.palette(for: traitCollection).panelColor; collectionView.reloadData(); categoryControl.reloadData() }
  open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) { super.traitCollectionDidChange(previousTraitCollection); applySkin() }
  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { collectionView === categoryControl ? PteIMUIEmojiCategory.allCases.count : items.count }
  public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    if collectionView === categoryControl {
      let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.categoryReuse, for: indexPath) as! PteIMUIEmojiPickerCell
      let category = PteIMUIEmojiCategory.allCases[indexPath.item]
      cell.configure(title: category.title(language: language), selected: category == selectedCategory, skin: skin)
      return cell
    }
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.emojiReuse, for: indexPath) as! PteIMUIEmojiPickerCell
    cell.configure(title: items[indexPath.item].id, selected: false, skin: skin)
    return cell
  }
  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    if collectionView === categoryControl { selectedCategory = PteIMUIEmojiCategory.allCases[indexPath.item]; categoryControl.reloadData() }
    else { onSelect?(items[indexPath.item]) }
  }
  public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    if collectionView === categoryControl { return CGSize(width: max(58, PteIMUIEmojiCategory.allCases[indexPath.item].title(language: language).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11)]).width + 18), height: 28) }
    return CGSize(width: 34, height: 34)
  }
}

private final class PteIMUIEmojiPickerCell: UICollectionViewCell {
  private let label = UILabel()
  override init(frame: CGRect) { super.init(frame: frame); label.translatesAutoresizingMaskIntoConstraints = false; label.textAlignment = .center; contentView.addSubview(label); NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), label.topAnchor.constraint(equalTo: contentView.topAnchor), label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)]) }
  required init?(coder: NSCoder) { nil }
  func configure(title: String, selected: Bool, skin: PteIMUISkin) { let palette = skin.theme.palette(for: traitCollection); label.text = title; label.font = title.count <= 2 ? .systemFont(ofSize: 25) : .systemFont(ofSize: 11, weight: .medium); label.textColor = palette.primaryTextColor; contentView.backgroundColor = selected ? palette.outgoingGradientStartColor.withAlphaComponent(0.18) : palette.panelItemColor; contentView.layer.cornerRadius = 9 }
}
