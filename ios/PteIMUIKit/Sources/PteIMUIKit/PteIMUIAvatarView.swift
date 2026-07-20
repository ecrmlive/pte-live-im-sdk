import UIKit

/**
 Reusable IM avatar. By default it is a circle; set `cornerRadius` to use a
 rounded-square or any host-owned shape. Images always use aspect fill and
 are clipped by this view.
 */
@MainActor public final class PteIMUIAvatarView: UIControl {
  public let imageView = UIImageView()
  public let textLabel = UILabel()
  public var cornerRadius: CGFloat? { didSet { applyShape() } }

  public override init(frame: CGRect = .zero) {
    super.init(frame: frame)
    clipsToBounds = true
    imageView.contentMode = .scaleAspectFill; imageView.clipsToBounds = true
    textLabel.textAlignment = .center
    [imageView, textLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor), imageView.trailingAnchor.constraint(equalTo: trailingAnchor), imageView.topAnchor.constraint(equalTo: topAnchor), imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      textLabel.leadingAnchor.constraint(equalTo: leadingAnchor), textLabel.trailingAnchor.constraint(equalTo: trailingAnchor), textLabel.topAnchor.constraint(equalTo: topAnchor), textLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }
  required init?(coder: NSCoder) { nil }
  public override func layoutSubviews() { super.layoutSubviews(); applyShape() }
  public func apply(image: UIImage?, text: String, textColor: UIColor, backgroundColor: UIColor) {
    imageView.image = image; imageView.isHidden = image == nil
    textLabel.text = text; textLabel.textColor = textColor; textLabel.isHidden = image != nil; textLabel.backgroundColor = backgroundColor
  }
  private func applyShape() {
    let radius = min(max(0, cornerRadius ?? bounds.height / 2), min(bounds.width, bounds.height) / 2)
    layer.cornerRadius = radius; imageView.layer.cornerRadius = radius; textLabel.layer.cornerRadius = radius
  }
}
