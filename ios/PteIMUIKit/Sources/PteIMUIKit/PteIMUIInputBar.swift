import UIKit
import PteIMSDK

/** A selection coming from the built-in emoji or more-action panel. */
public enum PteIMUIInputBarAction {
  case emoji(packageId: String, emojiId: String)
  case action(PteIMUIAction)
  case custom(PteIMUICustomInputAction)
}

/** A host-defined attachment item. The built-in grid reserves its first eight
 actions for media; up to four of these items can be appended by an integrator. */
public struct PteIMUICustomInputAction {
  public let id: String
  public let title: String
  public let icon: UIImage
  public init(id: String, title: String, icon: UIImage) {
    self.id = id; self.title = title; self.icon = icon
  }
}

/**
 Reusable UIKit input accessory for PteIMUIKit. It owns composer presentation
 and interaction; business actions remain host-owned.
 */
open class PteIMUIInputBar: UIView, UITextViewDelegate {
  public weak var delegate: PteIMUIInputBarDelegate?
  public var onSendText: ((String) -> Void)?
  public var onAction: ((PteIMUIInputBarAction) -> Void)?
  /** Lets a chat consume an emoji before it is inserted in the draft. */
  public var onEmojiSelected: ((String) -> Bool)?
  public var onVoiceRecordingChanged: ((Bool) -> Void)?
  public var onVoiceRecordingCancelled: (() -> Void)?
  public var skin: PteIMUISkin { didSet { theme = skin.theme; applySkin() } }
  public var enabledActions: Set<PteIMUIAction> = Set(PteIMUIAction.allCases) { didSet { rebuildMorePanel() } }
  /// Up to four host-owned business actions follow the built-in eight items.
  /// The grid never exceeds 12 tiles / three rows.
  public var customActions: [PteIMUICustomInputAction] = [] { didSet { rebuildMorePanel() } }
  /** A text draft accepts at most 200 user-perceived characters. */
  public var maximumCharacterCount: Int = 200
  /// Emoji catalogue configuration is forwarded to the bundled picker so an
  /// app can provide curated common expressions and raster custom stickers.
  public var emojiScope: PteIMUIEmojiScope {
    get { emojiPicker.scope }
    set { emojiPicker.scope = newValue }
  }
  public var commonEmojiItems: [PteIMUIEmojiItem] {
    get { emojiPicker.commonEmojiItems }
    set { emojiPicker.commonEmojiItems = newValue }
  }
  public var customEmojiItems: [PteIMUIEmojiItem] {
    get { emojiPicker.customEmojiItems }
    set { emojiPicker.customEmojiItems = newValue }
  }
  public var customImageEmojiItems: [PteIMUICustomEmojiImage] {
    get { emojiPicker.customImageEmojiItems }
    set { emojiPicker.customImageEmojiItems = newValue }
  }
  public var language: PteIMLanguage = .zhCN { didSet { applyCopy() } }
  public var theme: PteIMUITheme { didSet { applyTheme() } }
  public private(set) var voiceMode = false

  private enum Panel { case none, emoji, more }
  private var panel: Panel = .none { didSet { updatePanel() } }
  private let border = UIView()
  private let input = UITextView()
  private let placeholderLabel = UILabel()
  private let voiceButton = UIButton(type: .system)
  private let moreButton = UIButton(type: .system)
  private let emojiButton = UIButton(type: .system)
  private let sendButton = UIButton(type: .system)
  private let closePanelButton = UIButton(type: .system)
  private let holdToTalkButton = UIButton(type: .system)
  private let contentStack = UIStackView()
  private let panelView = UIView()
  private let panelDivider = UIView()
  private lazy var emojiPicker = PteIMUIEmojiPickerView(skin: skin)
  private let moreGrid = UIStackView()
  private var moreButtons: [UIButton] = []
  private var moreButtonActions: [ObjectIdentifier: PteIMUIInputBarAction] = [:]
  private let sendGradient = CAGradientLayer()
  private var inputHeightConstraint: NSLayoutConstraint!
  private var borderHeightConstraint: NSLayoutConstraint!
  private let minimumInputHeight: CGFloat = 40
  private let maximumInputHeight: CGFloat = 100
  private var moreGridHeightConstraint: NSLayoutConstraint!
  private enum VoiceState { case idle, recording, cancelling }
  private var voiceState: VoiceState = .idle

  public init(skin: PteIMUISkin = .default) {
    self.skin = skin; self.theme = skin.theme
    super.init(frame: .zero)
    configureViews()
    applyCopy()
    applyTheme()
  }
  public convenience init(theme: PteIMUITheme) { self.init(skin: PteIMUISkin(theme: theme)) }
  required public init?(coder: NSCoder) { nil }

  /** Current draft. Assigning it also refreshes the send-button visibility. */
  public var text: String {
    get { input.text ?? "" }
    set { input.text = String(newValue.prefix(maximumCharacterCount)); inputDidChange() }
  }
  public func clearText() { input.text = nil; inputDidChange() }
  public func endEditingInput() { endEditing(true) }
  /** Opens the bundled Emoji6-compatible Unicode picker. */
  public func openEmojiPanel() { leaveVoiceMode(); endEditing(true); panel = .emoji }
  /** Opens the configured attachment/business action grid. */
  public func openMorePanel() { leaveVoiceMode(); endEditing(true); panel = .more }
  public func closePanel() { panel = .none }

  private func configureViews() {
    translatesAutoresizingMaskIntoConstraints = false
    border.translatesAutoresizingMaskIntoConstraints = false
    // The composer itself is the surface. The text field is the rounded
    // lavender/dark pill from the supplied chat designs; it is not nested in
    // an additional outlined capsule.
    border.layer.cornerRadius = 0
    border.layer.borderWidth = 0
    addSubview(border)

    // The chat spec uses a 40pt interaction target for each composer control.
    // Keeping the field and controls on the same grid also prevents the
    // buttons from changing the composer height when a panel is opened.
    [voiceButton, moreButton, emojiButton].forEach {
      $0.tintColor = .label
      $0.widthAnchor.constraint(equalToConstant: 40).isActive = true
      $0.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }
    configureIcon(voiceButton, key: .inputVoice)
    configureIcon(moreButton, key: .inputMore)
    configureIcon(emojiButton, key: .inputEmoji)
    voiceButton.addTarget(self, action: #selector(toggleVoiceMode), for: .touchUpInside)
    moreButton.addTarget(self, action: #selector(toggleMore), for: .touchUpInside)
    emojiButton.addTarget(self, action: #selector(toggleEmoji), for: .touchUpInside)

    input.delegate = self
    input.font = .preferredFont(forTextStyle: .body)
    // iOS renders the localized keyboard action (e.g. “发送”) for this type.
    input.returnKeyType = .send
    input.adjustsFontForContentSizeCategory = true
    input.isScrollEnabled = false
    // Keep the insertion point and typed text away from the rounded field
    // edge: 10pt horizontally and 8pt from the top/bottom.
    input.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    input.textContainer.lineFragmentPadding = 0
    input.backgroundColor = .clear
    input.addSubview(placeholderLabel)
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    placeholderLabel.font = .preferredFont(forTextStyle: .body)
    placeholderLabel.numberOfLines = 1
    NSLayoutConstraint.activate([
      placeholderLabel.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 10),
      placeholderLabel.trailingAnchor.constraint(equalTo: input.trailingAnchor, constant: -10),
      placeholderLabel.centerYAnchor.constraint(equalTo: input.centerYAnchor)
    ])

    holdToTalkButton.layer.cornerRadius = 12
    holdToTalkButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
    holdToTalkButton.addTarget(self, action: #selector(voiceTouchDown), for: .touchDown)
    holdToTalkButton.addTarget(self, action: #selector(voiceDragExited), for: .touchDragExit)
    holdToTalkButton.addTarget(self, action: #selector(voiceDragEntered), for: .touchDragEnter)
    holdToTalkButton.addTarget(self, action: #selector(voiceTouchUpInside), for: .touchUpInside)
    holdToTalkButton.addTarget(self, action: #selector(voiceTouchCancelled), for: [.touchUpOutside, .touchCancel])
    holdToTalkButton.isHidden = true

    sendButton.setTitleColor(.white, for: .normal)
    sendButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    sendButton.layer.cornerRadius = 12
    sendButton.clipsToBounds = true
    sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
    sendButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
    sendButton.layer.insertSublayer(sendGradient, at: 0)

    configureIcon(closePanelButton, key: .inputClose)
    closePanelButton.accessibilityLabel = PteIMUILocalization.value("收起功能面板", "Close input panel", language: language)
    closePanelButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
    closePanelButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
    closePanelButton.isHidden = true
    closePanelButton.addTarget(self, action: #selector(closePanelTapped), for: .touchUpInside)

    // The attachment affordance remains available while a panel is open. It
    // is how the user switches directly between Emoji and More, exactly as in
    // the supplied chat artwork.
    [voiceButton, input, holdToTalkButton, emojiButton, moreButton, sendButton, closePanelButton].forEach { contentStack.addArrangedSubview($0) }
    contentStack.spacing = 4
    contentStack.alignment = .center
    border.addSubview(contentStack)
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    inputHeightConstraint = input.heightAnchor.constraint(equalToConstant: minimumInputHeight)
    borderHeightConstraint = border.heightAnchor.constraint(equalToConstant: minimumInputHeight + 12)
    NSLayoutConstraint.activate([
      border.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), border.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      border.topAnchor.constraint(equalTo: topAnchor, constant: 6), borderHeightConstraint,
      contentStack.leadingAnchor.constraint(equalTo: border.leadingAnchor, constant: 4), contentStack.trailingAnchor.constraint(equalTo: border.trailingAnchor, constant: -4),
      contentStack.topAnchor.constraint(equalTo: border.topAnchor), contentStack.bottomAnchor.constraint(equalTo: border.bottomAnchor),
      inputHeightConstraint,
      holdToTalkButton.heightAnchor.constraint(equalToConstant: 40)
    ])

    panelView.translatesAutoresizingMaskIntoConstraints = false
    panelView.isHidden = true
    addSubview(panelView)
    panelDivider.translatesAutoresizingMaskIntoConstraints = false
    panelDivider.isHidden = true
    panelDivider.isUserInteractionEnabled = false
    addSubview(panelDivider)
    NSLayoutConstraint.activate([
      panelView.leadingAnchor.constraint(equalTo: leadingAnchor), panelView.trailingAnchor.constraint(equalTo: trailingAnchor),
      // The emoji grid paints through the lower safe area so expressions reach
      // the screen edge. Its floating actions apply their own safe-area inset.
      panelView.topAnchor.constraint(equalTo: border.bottomAnchor), panelView.bottomAnchor.constraint(equalTo: bottomAnchor),
      panelView.heightAnchor.constraint(equalToConstant: 0),
      // A crisp boundary keeps the input composer visually distinct from the
      // emoji/function panel in both light and dark appearances.
      panelDivider.leadingAnchor.constraint(equalTo: panelView.leadingAnchor), panelDivider.trailingAnchor.constraint(equalTo: panelView.trailingAnchor), panelDivider.topAnchor.constraint(equalTo: panelView.topAnchor), panelDivider.heightAnchor.constraint(equalToConstant: 1)
    ])
    configurePanels()
    updateSendVisibility()
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    sendGradient.frame = sendButton.bounds
    updateInputHeightIfNeeded()
  }

  // The input bar is constructed before it is attached to the chat
  // controller. At that point it can still inherit the app's light trait even
  // when the chat applies a persisted/time-based dark override a moment
  // later. Reapply after attachment and every appearance transition so the
  // composer, picker and text field always use the same palette as the chat.
  public override func didMoveToWindow() {
    super.didMoveToWindow()
    applyTheme()
  }

  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    applyTheme()
  }

  open func configureIcon(_ button: UIButton, key: PteIMUIIconKey) {
    button.setImage(skin.icons.image(for: key, traitCollection: traitCollection), for: .normal)
    button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium), forImageIn: .normal)
  }

  private func configurePanels() {
    emojiPicker.onSelect = { [weak self] item in self?.selectEmoji(item.id) }
    emojiPicker.onBackspace = { [weak self] in self?.deleteLastDraftCharacter() }
    emojiPicker.onSend = { [weak self] in self?.sendTapped() }
    moreGrid.axis = .vertical; moreGrid.distribution = .fillEqually; moreGrid.spacing = 20
    populateMoreGrid()
    panelView.addSubview(emojiPicker); panelView.addSubview(moreGrid)
    emojiPicker.translatesAutoresizingMaskIntoConstraints = false
    moreGrid.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      emojiPicker.leadingAnchor.constraint(equalTo: panelView.leadingAnchor), emojiPicker.trailingAnchor.constraint(equalTo: panelView.trailingAnchor), emojiPicker.topAnchor.constraint(equalTo: panelView.topAnchor), emojiPicker.bottomAnchor.constraint(equalTo: panelView.bottomAnchor),
      moreGrid.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 16), moreGrid.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -16), moreGrid.centerYAnchor.constraint(equalTo: panelView.centerYAnchor)
    ])
    moreGridHeightConstraint = moreGrid.heightAnchor.constraint(equalToConstant: 170)
    moreGridHeightConstraint.isActive = true
    moreGrid.isHidden = true
  }

  private func rebuildMorePanel() {
    guard moreGrid.superview != nil else { return }
    populateMoreGrid()
    applyCopy()
  }

  private func populateMoreGrid() {
    moreButtons.removeAll(); moreButtonActions.removeAll()
    moreGrid.arrangedSubviews.forEach { moreGrid.removeArrangedSubview($0); $0.removeFromSuperview() }
    let standard: [PteIMUIInputBarAction] = [.image, .camera, .video, .location, .file, .redPacket, .gift, .order]
      .filter { enabledActions.contains($0) }
      .map(PteIMUIInputBarAction.action)
    let entries = Array((standard + customActions.prefix(4).map(PteIMUIInputBarAction.custom)).prefix(12))
    stride(from: 0, to: entries.count, by: 4).forEach { index in
      let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 20
      entries[index..<min(index + 4, entries.count)].forEach { selection in
        let button = UIButton(type: .system)
        button.heightAnchor.constraint(equalToConstant: 75).isActive = true
        button.addTarget(self, action: #selector(selectMoreAction(_:)), for: .touchUpInside)
        moreButtons.append(button); moreButtonActions[ObjectIdentifier(button)] = selection
        row.addArrangedSubview(button)
      }
      moreGrid.addArrangedSubview(row)
    }
    let rowCount = max(1, Int(ceil(Double(entries.count) / 4.0)))
    moreGridHeightConstraint?.constant = CGFloat(rowCount * 75 + max(0, rowCount - 1) * 20)
  }

  private func applySkin() { applyTheme() }

  private func applyTheme() {
    let palette = theme.palette(for: traitCollection)
    backgroundColor = palette.composerColor
    border.backgroundColor = .clear
    border.layer.borderWidth = 0
    border.layer.borderColor = UIColor.clear.cgColor
    input.textColor = palette.primaryTextColor
    input.tintColor = palette.outgoingGradientStartColor
    placeholderLabel.textColor = palette.secondaryTextColor
    [voiceButton, moreButton, emojiButton, closePanelButton].forEach { $0.tintColor = palette.iconColor }
    input.backgroundColor = palette.composerInputColor
    input.layer.cornerRadius = 12
    input.clipsToBounds = true
    updateVoiceButtonState()
    panelView.backgroundColor = palette.panelColor
    panelDivider.backgroundColor = palette.dividerColor
    sendGradient.colors = [palette.outgoingGradientStartColor.cgColor, palette.outgoingGradientEndColor.cgColor]
    emojiPicker.skin = skin; emojiPicker.language = language
    moreButtons.forEach {
      let button = $0
      button.tintColor = palette.iconColor
      button.backgroundColor = .clear
      button.layer.cornerRadius = 0
    }
    voiceButton.setImage(skin.icons.image(for: voiceMode ? .inputKeyboard : .inputVoice, traitCollection: traitCollection), for: .normal)
    emojiButton.setImage(skin.icons.image(for: panel == .emoji ? .inputEmojiActive : .inputEmoji, traitCollection: traitCollection), for: .normal)
    moreButton.setImage(skin.icons.image(for: panel == .more ? .inputMoreActive : .inputMore, traitCollection: traitCollection), for: .normal)
    configureIcon(closePanelButton, key: .inputClose)
  }

  private func applyCopy() {
        placeholderLabel.text = PteIMUILocalization.value("说点什么...", "Say something...", language: language)
    holdToTalkButton.setTitle(PteIMUILocalization.value("按住说话", "Hold to talk", language: language), for: .normal)
    sendButton.setTitle(PteIMUILocalization.value("发送", "Send", language: language), for: .normal)
    closePanelButton.accessibilityLabel = PteIMUILocalization.value("收起功能面板", "Close input panel", language: language)
    moreButtons.forEach { button in
      guard let selection = moreButtonActions[ObjectIdentifier(button)] else { return }
      var configuration = UIButton.Configuration.plain()
      switch selection {
      case let .action(action):
        configuration.image = skin.icons.image(for: iconKey(for: action), traitCollection: traitCollection)
        configuration.title = action.title(language: language)
      case let .custom(action):
        configuration.image = action.icon
        configuration.title = action.title
      case .emoji:
        return
      }
      configuration.imagePlacement = .top
      // A function tile is exactly 75pt: 52pt artwork, 8pt gap, then a
      // 15pt text line.  The supplied 156px source cuts are normalised to
      // 52pt by the icon provider and must not be inset by UIButton.
      configuration.imagePadding = 8
      configuration.contentInsets = .zero
      configuration.baseForegroundColor = theme.palette(for: traitCollection).iconColor
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
        var result = attributes
        // 13pt system text has a 15pt line height, matching the source tile.
        result.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        return result
      }
      button.configuration = configuration
    }
    applyTheme()
  }

  private func updatePanel() {
    let isOpen = panel != .none
    panelView.isHidden = !isOpen
    panelDivider.isHidden = !isOpen
    emojiPicker.isHidden = panel != .emoji
    moreGrid.isHidden = panel != .more
    // Keep the plus action in emoji mode. The supplied design does not replace
    // it with a close icon; tapping it switches directly to the More panel.
    moreButton.isHidden = false
    updateSendVisibility()
    closePanelButton.isHidden = true
    let moreHeight = moreGridHeightConstraint?.constant ?? 170
    // Emoji artwork, header and floating actions occupy a compact 338pt
    // panel; larger values leave an oversized blank grid below the content.
    panelView.constraints.first { $0.firstAttribute == .height }?.constant = isOpen ? (panel == .more ? moreHeight + 32 : 338) : 0
    applyTheme()
    superview?.setNeedsLayout()
  }

  @objc private func toggleVoiceMode() {
    voiceMode.toggle(); input.isHidden = voiceMode; holdToTalkButton.isHidden = !voiceMode; holdToTalkButton.isEnabled = true; holdToTalkButton.alpha = 1
    voiceState = .idle
    voiceButton.setImage(skin.icons.image(for: voiceMode ? .inputKeyboard : .inputVoice, traitCollection: traitCollection), for: .normal)
    panel = .none
  }
  private func leaveVoiceMode() {
    guard voiceMode else { return }
    voiceMode = false
    input.isHidden = false
    holdToTalkButton.isHidden = true
    voiceState = .idle
    voiceButton.setImage(skin.icons.image(for: .inputVoice, traitCollection: traitCollection), for: .normal)
  }
  @objc private func toggleEmoji() { panel == .emoji ? closePanel() : openEmojiPanel() }
  @objc private func toggleMore() { panel == .more ? closePanel() : openMorePanel() }
  @objc private func closePanelTapped() { closePanel() }
  @objc private func sendTapped() {
    let text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    input.text = nil
    panel = .none
    inputDidChange()
    delegate?.inputBar(self, didSendText: text)
    onSendText?(text)
  }
  @objc private func voiceTouchDown() { isVoiceRecordingCancelled = false; voiceState = .recording; updateVoiceButtonState(); delegate?.inputBar(self, voiceRecordingChanged: true); onVoiceRecordingChanged?(true) }
  @objc private func voiceDragExited() { guard voiceState == .recording else { return }; voiceState = .cancelling; updateVoiceButtonState() }
  @objc private func voiceDragEntered() { guard voiceState == .cancelling else { return }; voiceState = .recording; updateVoiceButtonState() }
  @objc private func voiceTouchUpInside() { finishVoiceRecording(cancelled: voiceState == .cancelling) }
  @objc private func voiceTouchCancelled() { finishVoiceRecording(cancelled: true) }
  private func finishVoiceRecording(cancelled: Bool) {
    voiceState = .idle; updateVoiceButtonState()
    isVoiceRecordingCancelled = cancelled
    if cancelled { delegate?.inputBarDidCancelVoiceRecording(self); onVoiceRecordingCancelled?() }
    delegate?.inputBar(self, voiceRecordingChanged: false); onVoiceRecordingChanged?(false)
  }
  /** True only during the completion callback following a drag-out cancel. */
  public private(set) var isVoiceRecordingCancelled = false
  private func updateVoiceButtonState() {
    let palette = theme.palette(for: traitCollection)
    switch voiceState {
    case .idle:
      holdToTalkButton.setTitle(PteIMUILocalization.value("按住说话", "Hold to talk", language: language), for: .normal)
      holdToTalkButton.backgroundColor = palette.composerInputColor
      holdToTalkButton.setTitleColor(palette.secondaryTextColor, for: .normal)
    case .recording:
      holdToTalkButton.setTitle(PteIMUILocalization.value("正在说话", "Talking", language: language), for: .normal)
      holdToTalkButton.backgroundColor = palette.outgoingGradientStartColor
      holdToTalkButton.setTitleColor(.white, for: .normal)
    case .cancelling:
      holdToTalkButton.setTitle(PteIMUILocalization.value("松开手取消录音", "Release to cancel", language: language), for: .normal)
      holdToTalkButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.88)
      holdToTalkButton.setTitleColor(.white, for: .normal)
    }
  }
  @objc private func selectMoreAction(_ sender: UIButton) {
    guard let value = moreButtonActions[ObjectIdentifier(sender)] else { return }
    panel = .none
    delegate?.inputBar(self, didSelect: value)
    onAction?(value)
  }
  private func selectEmoji(_ emojiId: String) {
    if onEmojiSelected?(emojiId) == true { return }
    // Emoji selection edits the draft at the caret. Sending remains explicit:
    // keyboard Send while typing, or the panel Send button while emoji is open.
    let current = input.text ?? ""
    let range = input.selectedRange
    let updated = (current as NSString).replacingCharacters(in: range, with: emojiId)
    guard updated.count <= maximumCharacterCount else { return }
    input.text = updated
    input.selectedRange = NSRange(location: range.location + (emojiId as NSString).length, length: 0)
    emojiPicker.selectedEmojiID = emojiId
    inputDidChange()
  }
  private func deleteLastDraftCharacter() {
    let current = input.text ?? ""
    let selection = input.selectedRange
    guard !current.isEmpty else { return }
    if selection.length > 0 {
      input.text = (current as NSString).replacingCharacters(in: selection, with: "")
      input.selectedRange = NSRange(location: selection.location, length: 0)
    } else if selection.location > 0 {
      let composed = (current as NSString).rangeOfComposedCharacterSequence(at: selection.location - 1)
      input.text = (current as NSString).replacingCharacters(in: composed, with: "")
      input.selectedRange = NSRange(location: composed.location, length: 0)
    }
    inputDidChange()
  }
  public func textViewDidChange(_ textView: UITextView) { inputDidChange() }
  public func textViewDidBeginEditing(_ textView: UITextView) {
    // A system keyboard and an in-app panel are mutually exclusive. This also
    // covers tapping the field while the emoji or attachment panel is visible.
    if panel != .none { panel = .none }
  }
  public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    if text == "\n" {
      // The iOS keyboard's Send key is the only send affordance in typing
      // mode. Existing/pasted line breaks still render in the multi-line view.
      sendTapped()
      return false
    }
    let current = textView.text ?? ""
    let updated = (current as NSString).replacingCharacters(in: range, with: text)
    return updated.count <= maximumCharacterCount
  }

  private func inputDidChange() {
    placeholderLabel.isHidden = !input.text.isEmpty
    updateSendVisibility()
    setNeedsLayout()
    superview?.setNeedsLayout()
  }

  private func updateInputHeightIfNeeded() {
    let availableWidth = input.bounds.width
    guard availableWidth > 0 else { return }
    let fittingHeight = ceil(input.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude)).height)
    let resolvedHeight = min(maximumInputHeight, max(minimumInputHeight, fittingHeight))
    let shouldScroll = fittingHeight > maximumInputHeight
    guard inputHeightConstraint.constant != resolvedHeight || input.isScrollEnabled != shouldScroll else { return }
    inputHeightConstraint.constant = resolvedHeight
    borderHeightConstraint.constant = resolvedHeight + 12
    input.isScrollEnabled = shouldScroll
    superview?.setNeedsLayout()
  }

  /// Typing mode sends through the keyboard return-key only. The explicit
  /// gradient Send control belongs exclusively to the emoji panel footer.
  private func updateSendVisibility() {
    sendButton.isHidden = true
  }

  private func iconKey(for action: PteIMUIAction) -> PteIMUIIconKey { switch action { case .image: return .panelImage; case .camera: return .panelCamera; case .video: return .panelVideo; case .voice: return .inputVoice; case .location: return .panelLocation; case .gift: return .panelGift; case .redPacket: return .panelRedPacket; case .order: return .panelOrder; case .file: return .panelFile } }
}
