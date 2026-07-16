import UIKit
import PteIMSDK

/**
 Cache-first conversation list. Subclass it to supply business display data,
 layout rows, handle avatars, or route C2C and group conversations differently.
 */
open class PteIMUIConversationListViewController: UITableViewController {
  public let client: PteIMSDK
  public var skin: PteIMUISkin { didSet { applySkin() } }
  public var onConversationSelected: ((PteIMUIConversationPresentation, PteIMUIConversationListViewController) -> Void)?
  public var onAvatarTapped: ((PteIMUIConversationPresentation, PteIMUIConversationListViewController) -> Void)?
  public var onAddRequested: ((PteIMUIConversationListViewController) -> Void)?
  /**
   Optional host-owned rows. Set this when a business directory already has
   names, avatars and unread counts; Core cursor/cache sync stays untouched.
   Set `nil` to return to the built-in local-conversation source.
   */
  public var hostPresentations: [PteIMUIConversationPresentation]? {
    didSet { guard isViewLoaded else { return }; reloadConversations() }
  }
  private var conversations: [PteIMConversation] = []
  private var visiblePresentations: [PteIMUIConversationPresentation] = []
  private var filteredPresentations: [PteIMUIConversationPresentation] = []
  private let listener = PteIMListener()
  private lazy var chrome = PteIMUIListChrome(title: title ?? "Chats")

  public init(client: PteIMSDK, skin: PteIMUISkin = .default) {
    self.client = client; self.skin = skin; super.init(style: .plain)
    title = PteIMUILocalization.value("会话", "Chats", language: client.appearance.language)
  }
  public convenience init(client: PteIMSDK, theme: PteIMUITheme) { self.init(client: client, skin: PteIMUISkin(theme: theme)) }
  required public init?(coder: NSCoder) { nil }
  deinit { client.removeListener(listener) }

  open override func viewDidLoad() {
    super.viewDidLoad()
    tableView.register(PteIMUIConversationCell.self, forCellReuseIdentifier: PteIMUIConversationCell.reuseIdentifier)
    tableView.separatorStyle = .none
    tableView.tableHeaderView = chrome
    chrome.onSearchChanged = { [weak self] query in self?.filterConversations(query) }
    chrome.onAppearanceTapped = { [weak self] in self?.toggleAppearance() }
    chrome.onLanguageTapped = { [weak self] in self?.toggleLanguage() }
    chrome.onAddTapped = { [weak self] in guard let self else { return }; self.onAddRequested?(self) }
    refreshControl = UIRefreshControl(); refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
    bindClient(); reloadConversations(); applySkin()
  }
  open override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: animated)
  }
  open override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutChromeIfNeeded()
  }

  @objc open func refresh() { client.syncNow(); reloadConversations(); refreshControl?.endRefreshing() }
  open func reloadConversations() {
    if let hostPresentations {
      conversations = []
      visiblePresentations = hostPresentations
      filteredPresentations = hostPresentations
      tableView.reloadData()
      return
    }
    conversations = (try? client.localConversations(limit: 100)) ?? []
    visiblePresentations = conversations.map { presentation(for: $0) }
    filteredPresentations = visiblePresentations
    tableView.reloadData()
  }

  /** Override to use your member/group directory for nickname, avatar and unread count. */
  open func presentation(for conversation: PteIMConversation) -> PteIMUIConversationPresentation {
    let rendered = PteIMUIMessageText.render(conversation.lastMessage, language: client.appearance.language).replacingOccurrences(of: "\n", with: " · ")
    return PteIMUIConversationPresentation(conversationId: conversation.conversationId, title: conversation.conversationId, subtitle: rendered, avatarText: PteIMUIMessageText.avatarText(for: conversation.conversationId), updatedAt: Date(timeIntervalSince1970: TimeInterval(conversation.updatedAt) / 1000))
  }

  /** Override to install a custom subclass or change every individual row. */
  open func configure(cell: PteIMUIConversationCell, presentation: PteIMUIConversationPresentation, at indexPath: IndexPath) {
    cell.configure(presentation: presentation, style: skin.list, palette: skin.theme.palette(for: traitCollection), icons: skin.icons)
  }
  open func didTapAvatar(_ presentation: PteIMUIConversationPresentation) { onAvatarTapped?(presentation, self) }
  open func didSelectConversation(_ presentation: PteIMUIConversationPresentation) {
    if let onConversationSelected { onConversationSelected(presentation, self); return }
    let chat = makeChatViewController(for: presentation)
    navigationController?.pushViewController(chat, animated: true)
  }
  /** Override for different single/group chat controllers. */
  open func makeChatViewController(for presentation: PteIMUIConversationPresentation) -> PteIMUIChatViewController {
    PteIMUIChatViewController(client: client, conversationId: presentation.conversationId, title: presentation.title, skin: skin)
  }

  private func bindClient() {
    listener.onMessage = { [weak self] _ in DispatchQueue.main.async { self?.reloadConversations() } }
    listener.onMessageStateChanged = { [weak self] _, _ in DispatchQueue.main.async { self?.reloadConversations() } }
    client.addListener(listener)
  }
  private func applySkin() {
    guard isViewLoaded else { return }
    let palette = skin.theme.palette(for: traitCollection)
    tableView.backgroundColor = palette.backgroundColor; tableView.rowHeight = skin.list.rowHeight
    refreshControl?.tintColor = palette.outgoingGradientStartColor; navigationController?.navigationBar.tintColor = palette.iconColor
    chrome.apply(palette: palette, title: title ?? "Chats", language: client.appearance.language)
    layoutChromeIfNeeded(force: true)
    tableView.reloadData()
  }
  open override func traitCollectionDidChange(_ previous: UITraitCollection?) { super.traitCollectionDidChange(previous); if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { applySkin() } }
  open override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filteredPresentations.count }
  open override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: PteIMUIConversationCell.reuseIdentifier, for: indexPath) as! PteIMUIConversationCell
    let item = filteredPresentations[indexPath.row]; configure(cell: cell, presentation: item, at: indexPath)
    cell.onAvatarTapped = { [weak self] in self?.didTapAvatar(item) }; return cell
  }
  open override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); didSelectConversation(filteredPresentations[indexPath.row]) }

  private func filterConversations(_ query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    filteredPresentations = trimmed.isEmpty ? visiblePresentations : visiblePresentations.filter {
      $0.title.localizedCaseInsensitiveContains(trimmed) || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }
    tableView.reloadData()
  }
  private func layoutChromeIfNeeded(force: Bool = false) {
    let size = CGSize(width: tableView.bounds.width, height: 122)
    guard force || chrome.frame.size != size else { return }
    chrome.frame = CGRect(origin: .zero, size: size)
    tableView.tableHeaderView = chrome
  }
  private func toggleAppearance() {
    let mode: PteIMThemeMode = traitCollection.userInterfaceStyle == .dark ? .light : .dark
    client.updateAppearance(themeMode: mode, language: client.appearance.language)
  }
  private func toggleLanguage() {
    let language: PteIMLanguage = client.appearance.language == .enUS ? .zhCN : .enUS
    client.updateAppearance(themeMode: client.appearance.themeMode, language: language)
    title = PteIMUILocalization.value("会话", "Chats", language: language)
    applySkin()
  }
}

open class PteIMUIConversationCell: UITableViewCell {
  public static let reuseIdentifier = "PteIMUIConversationCell"
  public var onAvatarTapped: (() -> Void)?
  public let avatarButton = UIButton(type: .custom)
  public let avatarImageView = UIImageView()
  public let avatarLabel = UILabel()
  public let titleLabel = UILabel()
  public let subtitleLabel = UILabel()
  public let timeLabel = UILabel()
  public let unreadLabel = UILabel()
  public let separator = UIView()
  public let chevron = UIImageView()

  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier); selectionStyle = .none; backgroundColor = .clear
    [avatarButton, titleLabel, subtitleLabel, timeLabel, unreadLabel, separator, chevron].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
    avatarButton.addSubview(avatarImageView); avatarButton.addSubview(avatarLabel); avatarButton.addTarget(self, action: #selector(tapAvatar), for: .touchUpInside)
    [avatarImageView, avatarLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    avatarImageView.contentMode = .scaleAspectFill; avatarImageView.clipsToBounds = true; avatarLabel.textAlignment = .center
    subtitleLabel.numberOfLines = 1; unreadLabel.textAlignment = .center; unreadLabel.clipsToBounds = true
    NSLayoutConstraint.activate([
      avatarButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), avatarButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), avatarButton.widthAnchor.constraint(equalToConstant: 42), avatarButton.heightAnchor.constraint(equalTo: avatarButton.widthAnchor),
      avatarImageView.leadingAnchor.constraint(equalTo: avatarButton.leadingAnchor), avatarImageView.trailingAnchor.constraint(equalTo: avatarButton.trailingAnchor), avatarImageView.topAnchor.constraint(equalTo: avatarButton.topAnchor), avatarImageView.bottomAnchor.constraint(equalTo: avatarButton.bottomAnchor),
      avatarLabel.leadingAnchor.constraint(equalTo: avatarButton.leadingAnchor), avatarLabel.trailingAnchor.constraint(equalTo: avatarButton.trailingAnchor), avatarLabel.topAnchor.constraint(equalTo: avatarButton.topAnchor), avatarLabel.bottomAnchor.constraint(equalTo: avatarButton.bottomAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: avatarButton.trailingAnchor, constant: 13), titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
      subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4), subtitleLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
      timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20), timeLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
      unreadLabel.trailingAnchor.constraint(equalTo: timeLabel.trailingAnchor), unreadLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 8), unreadLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18), unreadLabel.heightAnchor.constraint(equalToConstant: 18),
      separator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), separator.heightAnchor.constraint(equalToConstant: 1),
      chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18), chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), chevron.widthAnchor.constraint(equalToConstant: 12), chevron.heightAnchor.constraint(equalToConstant: 16)
    ])
  }
  required public init?(coder: NSCoder) { nil }
  @objc private func tapAvatar() { onAvatarTapped?() }
  open func configure(presentation: PteIMUIConversationPresentation, style: PteIMUIListStyle, palette: PteIMUIThemePalette, icons: PteIMUIIconProvider = PteIMUISystemIconProvider()) {
    // The reference skin keeps list rows on the page's lavender canvas. Hosts
    // that need card rows can still supply `cellBackgroundColor` explicitly.
    contentView.backgroundColor = style.cellBackgroundColor ?? palette.backgroundColor; contentView.layer.cornerRadius = style.cellCornerRadius
    avatarButton.constraints.filter { $0.firstAttribute == .width }.first?.constant = style.avatarSize
    avatarButton.layer.cornerRadius = style.avatarSize / 2; avatarButton.clipsToBounds = true
    avatarImageView.image = presentation.avatarImage; avatarImageView.isHidden = presentation.avatarImage == nil
    avatarLabel.isHidden = presentation.avatarImage != nil; avatarLabel.text = presentation.avatarText; avatarLabel.font = style.avatarFont; avatarLabel.textColor = style.avatarTextColor; avatarLabel.backgroundColor = presentation.avatarBackgroundColor ?? palette.outgoingGradientEndColor
    titleLabel.text = presentation.title; titleLabel.font = style.titleFont; titleLabel.textColor = style.titleColor ?? palette.primaryTextColor
    subtitleLabel.text = presentation.subtitle; subtitleLabel.font = style.subtitleFont; subtitleLabel.textColor = style.subtitleColor ?? palette.secondaryTextColor
    timeLabel.text = presentation.updatedAt.map { Self.timeFormatter.string(from: $0) }; timeLabel.font = style.timeFont; timeLabel.textColor = style.timeColor ?? palette.secondaryTextColor
    unreadLabel.text = presentation.unreadCount > 0 ? "\(presentation.unreadCount)" : nil; unreadLabel.isHidden = presentation.unreadCount == 0; unreadLabel.font = style.unreadFont; unreadLabel.textColor = style.unreadTextColor; unreadLabel.backgroundColor = style.unreadBackgroundColor ?? UIColor.systemRed; unreadLabel.layer.cornerRadius = 9
    separator.backgroundColor = style.separatorColor ?? palette.dividerColor; separator.isHidden = !style.showsSeparator
    chevron.image = icons.image(for: .chevron, traitCollection: traitCollection); chevron.tintColor = style.chevronColor ?? palette.secondaryTextColor; chevron.isHidden = !style.showsChevron
  }
  private static let timeFormatter: DateFormatter = { let value = DateFormatter(); value.dateFormat = "HH:mm"; return value }()
}
