import UIKit
import PteIMSDK

/** A selection coming from the built-in emoji or more-action panel. */
public enum PteIMUIInputBarAction {
  case emoji(packageId: String, emojiId: String)
  case action(PteIMUIAction)
}

/**
 Reusable UIKit input accessory for PteIMUIKit. It owns presentation and
 interaction only; recording, pickers and business flows remain host-owned.
 */
open class PteIMUIInputBar: UIView, UITextFieldDelegate {
  public var onSendText: ((String) -> Void)?
  public var onAction: ((PteIMUIInputBarAction) -> Void)?
  public var onVoiceRecordingChanged: ((Bool) -> Void)?
  public var skin: PteIMUISkin { didSet { theme = skin.theme; applySkin() } }
  public var enabledActions: Set<PteIMUIAction> = Set(PteIMUIAction.allCases) { didSet { rebuildMorePanel() } }
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
  private lazy var emojiPicker = PteIMUIEmojiPickerView(skin: skin)
  private let moreGrid = UIStackView()
  private var moreButtons: [(UIButton, PteIMUIAction)] = []
  private let sendGradient = CAGradientLayer()

  public init(skin: PteIMUISkin = .default) {
    self.skin = skin; self.theme = skin.theme
    super.init(frame: .zero)
    configureViews()
    applyCopy()
    applyTheme()
  }
  public convenience init(theme: PteIMUITheme) { self.init(skin: PteIMUISkin(theme: theme)) }
  required public init?(coder: NSCoder) { nil }

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
    configureIcon(voiceButton, key: .voice)
    configureIcon(moreButton, key: .add)
    configureIcon(emojiButton, key: .emoji)
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

  open func configureIcon(_ button: UIButton, key: PteIMUIIconKey) {
    button.setImage(skin.icons.image(for: key, traitCollection: traitCollection), for: .normal)
    button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium), forImageIn: .normal)
  }

  private func configurePanels() {
    emojiPicker.onSelect = { [weak self] item in self?.selectEmoji(item.id) }
    moreGrid.axis = .vertical; moreGrid.distribution = .fillEqually; moreGrid.spacing = 8
    let actions: [PteIMUIAction] = [.image, .camera, .video, .location, .redPacket, .order, .file, .gift].filter { enabledActions.contains($0) }
    stride(from: 0, to: actions.count, by: 4).forEach { index in
      let row = UIStackView()
      row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 8
      actions[index..<min(index + 4, actions.count)].forEach { action in
        let button = UIButton(type: .system)
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption2)
        button.tag = actionIndex(action)
        button.setImage(skin.icons.image(for: iconKey(for: action), traitCollection: traitCollection), for: .normal)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold), forImageIn: .normal)
        button.addTarget(self, action: #selector(selectMoreAction(_:)), for: .touchUpInside)
        row.addArrangedSubview(button)
        moreButtons.append((button, action))
      }
      moreGrid.addArrangedSubview(row)
    }
    panelView.addSubview(emojiPicker); panelView.addSubview(moreGrid)
    [emojiPicker, moreGrid].forEach { stack in
      stack.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16), stack.centerYAnchor.constraint(equalTo: panelView.centerYAnchor)])
    }
    emojiPicker.heightAnchor.constraint(equalToConstant: 112).isActive = true
    moreGrid.heightAnchor.constraint(equalToConstant: 144).isActive = true
    moreGrid.isHidden = true
  }

  private func rebuildMorePanel() {
    guard moreGrid.superview != nil else { return }
    moreButtons.removeAll(); moreGrid.arrangedSubviews.forEach { moreGrid.removeArrangedSubview($0); $0.removeFromSuperview() }
    let actions: [PteIMUIAction] = [.image, .camera, .video, .location, .redPacket, .order, .file, .gift].filter { enabledActions.contains($0) }
    stride(from: 0, to: actions.count, by: 4).forEach { index in
      let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 8
      actions[index..<min(index + 4, actions.count)].forEach { action in
        let button = UIButton(type: .system); button.tag = actionIndex(action); button.setImage(skin.icons.image(for: iconKey(for: action), traitCollection: traitCollection), for: .normal); button.addTarget(self, action: #selector(selectMoreAction(_:)), for: .touchUpInside); row.addArrangedSubview(button); moreButtons.append((button, action))
      }
      moreGrid.addArrangedSubview(row)
    }
    applyCopy()
  }

  private func applySkin() { applyTheme() }

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
    emojiPicker.skin = skin; emojiPicker.language = language
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
      configuration.image = skin.icons.image(for: iconKey(for: action), traitCollection: traitCollection)
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
    emojiPicker.isHidden = panel != .emoji
    moreGrid.isHidden = panel != .more
    panelView.constraints.first { $0.firstAttribute == .height }?.constant = isOpen ? (panel == .more ? 170 : 150) : 0
    superview?.setNeedsLayout()
  }

  @objc private func toggleVoiceMode() {
    voiceMode.toggle(); input.isHidden = voiceMode; holdToTalkButton.isHidden = !voiceMode
    voiceButton.setImage(skin.icons.image(for: voiceMode ? .keyboard : .voice, traitCollection: traitCollection), for: .normal)
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

  private func actionIndex(_ action: PteIMUIAction) -> Int { switch action { case .image: return 0; case .camera: return 1; case .video: return 2; case .location: return 3; case .redPacket: return 4; case .order: return 5; case .file: return 6; case .gift: return 7; case .voice: return -1 } }
  private func actionForIndex(_ index: Int) -> PteIMUIAction? { switch index { case 0: return .image; case 1: return .camera; case 2: return .video; case 3: return .location; case 4: return .redPacket; case 5: return .order; case 6: return .file; case 7: return .gift; default: return nil } }
  private func iconKey(for action: PteIMUIAction) -> PteIMUIIconKey { switch action { case .image: return .image; case .camera: return .camera; case .video: return .video; case .voice: return .voice; case .location: return .location; case .gift: return .gift; case .redPacket: return .redPacket; case .order: return .order; case .file: return .file } }
}
