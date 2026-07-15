import UIKit
import PteIMSDK

/** A selection coming from the built-in emoji or more-action panel. */
public enum PteIMUIInputBarAction {
  case emoji(packageId: String, emojiId: String)
  case action(PteIMUIAction)
}

/**
 Reusable UIKit input accessory for PteIMUIkit. It owns presentation and
 interaction only; recording, pickers and business flows remain host-owned.
 */
public final class PteIMUIInputBar: UIView, UITextFieldDelegate {
  public var onSendText: ((String) -> Void)?
  public var onAction: ((PteIMUIInputBarAction) -> Void)?
  public var onVoiceRecordingChanged: ((Bool) -> Void)?
  public var language: PteIMLanguage = .zhCN { didSet { applyCopy() } }
  public var theme: PteIMUITheme { didSet { applyTheme() } }
  public private(set) var voiceMode = false

  private enum Panel { case none, emoji, more }
  private var panel: Panel = .none { didSet { updatePanel() } }
  private let border = UIView()
  private let input = UITextField()
  private let voiceButton = UIButton(type: .system)
  private let moreButton = UIButton(type: .system)
  private let emojiButton = UIButton(type: .system)
  private let sendButton = UIButton(type: .system)
  private let holdToTalkButton = UIButton(type: .system)
  private let panelView = UIView()
  private let emojiStack = UIStackView()
  private let moreGrid = UIStackView()
  private var moreButtons: [(UIButton, PteIMUIAction)] = []
  private let sendGradient = CAGradientLayer()

  public init(theme: PteIMUITheme = .default) {
    self.theme = theme
    super.init(frame: .zero)
    configureViews()
    applyCopy()
    applyTheme()
  }
  required init?(coder: NSCoder) { nil }

  public func clearText() { input.text = nil }
  public func endEditingInput() { endEditing(true) }

  private func configureViews() {
    translatesAutoresizingMaskIntoConstraints = false
    border.translatesAutoresizingMaskIntoConstraints = false
    border.layer.cornerRadius = 23
    border.layer.borderWidth = 1
    addSubview(border)

    [voiceButton, moreButton, emojiButton].forEach {
      $0.tintColor = .label
      $0.widthAnchor.constraint(equalToConstant: 34).isActive = true
      $0.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    configureIcon(voiceButton, symbol: "mic")
    configureIcon(moreButton, symbol: "plus")
    configureIcon(emojiButton, symbol: "face.smiling")
    voiceButton.addTarget(self, action: #selector(toggleVoiceMode), for: .touchUpInside)
    moreButton.addTarget(self, action: #selector(toggleMore), for: .touchUpInside)
    emojiButton.addTarget(self, action: #selector(toggleEmoji), for: .touchUpInside)

    input.delegate = self
    input.borderStyle = .none
    input.font = .preferredFont(forTextStyle: .body)
    input.returnKeyType = .send
    input.adjustsFontForContentSizeCategory = true

    holdToTalkButton.layer.cornerRadius = 16
    holdToTalkButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
    holdToTalkButton.addTarget(self, action: #selector(voiceTouchDown), for: .touchDown)
    holdToTalkButton.addTarget(self, action: #selector(voiceTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    holdToTalkButton.isHidden = true

    sendButton.setTitleColor(.white, for: .normal)
    sendButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    sendButton.layer.cornerRadius = 18
    sendButton.clipsToBounds = true
    sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
    sendButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
    sendButton.layer.insertSublayer(sendGradient, at: 0)

    let content = UIStackView(arrangedSubviews: [voiceButton, input, holdToTalkButton, moreButton, emojiButton, sendButton])
    content.spacing = 6
    content.alignment = .center
    border.addSubview(content)
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      border.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), border.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      border.topAnchor.constraint(equalTo: topAnchor, constant: 8), border.heightAnchor.constraint(equalToConstant: 46),
      content.leadingAnchor.constraint(equalTo: border.leadingAnchor, constant: 5), content.trailingAnchor.constraint(equalTo: border.trailingAnchor, constant: -5),
      content.topAnchor.constraint(equalTo: border.topAnchor), content.bottomAnchor.constraint(equalTo: border.bottomAnchor),
      holdToTalkButton.heightAnchor.constraint(equalToConstant: 32)
    ])

    panelView.translatesAutoresizingMaskIntoConstraints = false
    panelView.isHidden = true
    addSubview(panelView)
    NSLayoutConstraint.activate([
      panelView.leadingAnchor.constraint(equalTo: leadingAnchor), panelView.trailingAnchor.constraint(equalTo: trailingAnchor),
      panelView.topAnchor.constraint(equalTo: border.bottomAnchor, constant: 8), panelView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
      panelView.heightAnchor.constraint(equalToConstant: 0)
    ])
    configurePanels()
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    sendGradient.frame = sendButton.bounds
  }

  private func configureIcon(_ button: UIButton, symbol: String) {
    button.setImage(UIImage(systemName: symbol), for: .normal)
    button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium), forImageIn: .normal)
  }

  private func configurePanels() {
    emojiStack.axis = .horizontal; emojiStack.distribution = .fillEqually; emojiStack.spacing = 8
    ["smile_001", "smile_002", "wave_001", "heart_001", "thumb_001", "party_001"].forEach { emojiId in
      let button = UIButton(type: .system)
      button.setTitle(emojiGlyph(for: emojiId), for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 25)
      button.accessibilityLabel = emojiId
      button.addAction(UIAction { [weak self] _ in self?.selectEmoji(emojiId) }, for: .touchUpInside)
      emojiStack.addArrangedSubview(button)
    }
    moreGrid.axis = .vertical; moreGrid.distribution = .fillEqually; moreGrid.spacing = 8
    let actions: [PteIMUIAction] = [.image, .video, .location, .gift, .redPacket, .order]
    stride(from: 0, to: actions.count, by: 3).forEach { index in
      let row = UIStackView()
      row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 8
      actions[index..<min(index + 3, actions.count)].forEach { action in
        let button = UIButton(type: .system)
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption2)
        button.tag = actionIndex(action)
        button.setImage(UIImage(systemName: symbol(for: action)), for: .normal)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        button.addTarget(self, action: #selector(selectMoreAction(_:)), for: .touchUpInside)
        row.addArrangedSubview(button)
        moreButtons.append((button, action))
      }
      moreGrid.addArrangedSubview(row)
    }
    panelView.addSubview(emojiStack); panelView.addSubview(moreGrid)
    [emojiStack, moreGrid].forEach { stack in
      stack.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16), stack.centerYAnchor.constraint(equalTo: panelView.centerYAnchor)])
    }
    emojiStack.heightAnchor.constraint(equalToConstant: 56).isActive = true
    moreGrid.heightAnchor.constraint(equalToConstant: 96).isActive = true
    moreGrid.isHidden = true
  }

  private func applyTheme() {
    let palette = theme.palette(for: traitCollection)
    backgroundColor = palette.composerColor
    border.backgroundColor = palette.surfaceColor
    border.layer.borderColor = palette.dividerColor.cgColor
    input.textColor = palette.primaryTextColor
    input.tintColor = palette.outgoingGradientStartColor
    input.attributedPlaceholder = NSAttributedString(string: input.placeholder ?? "", attributes: [.foregroundColor: palette.secondaryTextColor])
    [voiceButton, moreButton, emojiButton].forEach { $0.tintColor = palette.iconColor }
    holdToTalkButton.backgroundColor = palette.panelItemColor
    holdToTalkButton.setTitleColor(palette.primaryTextColor, for: .normal)
    panelView.backgroundColor = palette.panelColor
    sendGradient.colors = [palette.outgoingGradientStartColor.cgColor, palette.outgoingGradientEndColor.cgColor]
    emojiStack.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { $0.tintColor = palette.iconColor; $0.backgroundColor = palette.panelItemColor; $0.layer.cornerRadius = 14 }
    moreButtons.forEach { button, _ in
      button.tintColor = palette.iconColor
      button.backgroundColor = palette.panelItemColor
      button.layer.cornerRadius = 13
    }
  }

  private func applyCopy() {
    input.placeholder = PteIMUILocalization.value("输入消息", "Message", language: language)
    holdToTalkButton.setTitle(PteIMUILocalization.value("按住说话", "Hold to talk", language: language), for: .normal)
    sendButton.setTitle(PteIMUILocalization.value("发送", "Send", language: language), for: .normal)
    moreButtons.forEach { button, action in
      var configuration = UIButton.Configuration.plain()
      configuration.image = UIImage(systemName: symbol(for: action))
      configuration.imagePlacement = .top
      configuration.imagePadding = 3
      configuration.baseForegroundColor = theme.palette(for: traitCollection).iconColor
      configuration.title = action.title(language: language)
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
      button.configuration = configuration
    }
    applyTheme()
  }

  private func updatePanel() {
    let isOpen = panel != .none
    panelView.isHidden = !isOpen
    emojiStack.isHidden = panel != .emoji
    moreGrid.isHidden = panel != .more
    panelView.constraints.first { $0.firstAttribute == .height }?.constant = isOpen ? 104 : 0
    superview?.setNeedsLayout()
  }

  @objc private func toggleVoiceMode() {
    voiceMode.toggle(); input.isHidden = voiceMode; holdToTalkButton.isHidden = !voiceMode
    voiceButton.setImage(UIImage(systemName: voiceMode ? "keyboard" : "mic"), for: .normal)
    panel = .none
  }
  @objc private func toggleEmoji() { endEditing(true); panel = panel == .emoji ? .none : .emoji }
  @objc private func toggleMore() { endEditing(true); panel = panel == .more ? .none : .more }
  @objc private func sendTapped() { let text = input.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; guard !text.isEmpty else { return }; onSendText?(text); input.text = nil; panel = .none }
  @objc private func voiceTouchDown() { holdToTalkButton.alpha = 0.62; onVoiceRecordingChanged?(true) }
  @objc private func voiceTouchUp() { holdToTalkButton.alpha = 1; onVoiceRecordingChanged?(false) }
  @objc private func selectMoreAction(_ sender: UIButton) { guard let action = actionForIndex(sender.tag) else { return }; panel = .none; onAction?(.action(action)) }
  private func selectEmoji(_ emojiId: String) { panel = .none; onAction?(.emoji(packageId: "default", emojiId: emojiId)) }
  public func textFieldShouldReturn(_ textField: UITextField) -> Bool { sendTapped(); return false }

  private func emojiGlyph(for id: String) -> String { switch id { case "smile_001": return "☺︎"; case "smile_002": return "✦"; case "wave_001": return "◌"; case "heart_001": return "♥"; case "thumb_001": return "✓"; default: return "✺" } }
  private func actionIndex(_ action: PteIMUIAction) -> Int { switch action { case .image: return 0; case .video: return 1; case .location: return 2; case .gift: return 3; case .redPacket: return 4; case .order: return 5; case .voice: return -1 } }
  private func actionForIndex(_ index: Int) -> PteIMUIAction? { switch index { case 0: return .image; case 1: return .video; case 2: return .location; case 3: return .gift; case 4: return .redPacket; case 5: return .order; default: return nil } }
  private func symbol(for action: PteIMUIAction) -> String { switch action { case .image: return "photo"; case .video: return "video"; case .voice: return "mic"; case .location: return "location"; case .gift: return "gift"; case .redPacket: return "yensign.circle"; case .order: return "bag" } }
}
