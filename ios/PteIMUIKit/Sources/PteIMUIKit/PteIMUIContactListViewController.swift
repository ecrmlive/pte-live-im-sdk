import UIKit
import PteIMSDK

/** Data source used by the built-in contact surface. `custom` keeps ownership with the host app. */
public enum PteIMUIContactListMode: Sendable {
  case friends
  case follows
  case groups
  case custom
}

/**
 SDK-driven, cursor-paginated contact and group list. Hosts can retain full
 ownership by using `.custom`, assigning [contacts], or overriding the open
 mapping, loading, avatar and navigation hooks.
 */
open class PteIMUIContactListViewController: UITableViewController {
  public let client: PteIMSDK
  public let mode: PteIMUIContactListMode
  public var skin: PteIMUISkin { didSet { applySkin() } }
  public var contacts: [PteIMUIContactPresentation] = [] { didSet { filteredContacts = contacts; if isViewLoaded { tableView.reloadData() } } }
  public var onAvatarTapped: ((PteIMUIContactPresentation, PteIMUIContactListViewController) -> Void)?
  public var onContactSelected: ((PteIMUIContactPresentation, PteIMUIContactListViewController) -> Void)?
  public var onLoadError: ((Error, PteIMUIContactListViewController) -> Void)?
  public var onAddRequested: ((PteIMUIContactListViewController) -> Void)?
  public private(set) var isLoading = false
  public private(set) var hasMore = false
  private var nextCursor = ""
  private lazy var chrome = PteIMUIListChrome(title: title ?? "Contacts", showsQuickActions: true)
  private let listener = PteIMListener()
  private lazy var appearanceController = PteIMUIAppearanceController(client: client, viewController: self)
  private var filteredContacts: [PteIMUIContactPresentation] = []
  private var contactSections: [(title: String?, values: [PteIMUIContactPresentation])] {
    var orderedTitles: [String?] = []
    var valuesByTitle: [String: [PteIMUIContactPresentation]] = [:]
    for contact in filteredContacts {
      let title = contact.sectionTitle
      let key = title ?? "\u{0}"
      if valuesByTitle[key] == nil { orderedTitles.append(title); valuesByTitle[key] = [] }
      valuesByTitle[key, default: []].append(contact)
    }
    return orderedTitles.map { ($0, valuesByTitle[$0 ?? "\u{0}"] ?? []) }
  }

  public init(client: PteIMSDK, mode: PteIMUIContactListMode = .friends, skin: PteIMUISkin = .default) {
    self.client = client; self.mode = mode; self.skin = skin; super.init(style: .plain)
    title = Self.title(for: mode, language: client.appearance.language)
  }
  required public init?(coder: NSCoder) { nil }
  deinit { client.removeListener(listener) }
  open override func viewDidLoad() {
    super.viewDidLoad(); registerContactCells(in: tableView); tableView.separatorStyle = .none
    tableView.tableHeaderView = chrome
    chrome.onSearchChanged = { [weak self] query in self?.filterContacts(query) }
    chrome.onAddTapped = { [weak self] in guard let self else { return }; self.onAddRequested?(self) }
    refreshControl = UIRefreshControl(); refreshControl?.addTarget(self, action: #selector(reloadContacts), for: .valueChanged); bindClient(); appearanceController.start(); applySkin(); reloadContacts()
  }
  open override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    appearanceController.refresh()
    navigationController?.setNavigationBarHidden(true, animated: animated)
  }
  open override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutChromeIfNeeded()
  }
  /** Restarts the SDK cursor from the first page. In `.custom` mode this only reloads the host-provided rows. */
  @objc open func reloadContacts() {
    nextCursor = ""; hasMore = false
    guard mode != .custom else { refreshControl?.endRefreshing(); tableView.reloadData(); return }
    loadNextPage(replacing: true)
  }
  /** Loads one server cursor page. Override only when an application needs a different directory API. */
  open func loadNextPage(replacing: Bool = false) {
    guard mode != .custom, !isLoading, replacing || hasMore || contacts.isEmpty else { return }
    isLoading = true
    let cursor = replacing ? "" : nextCursor
    Task { [weak self] in
      guard let self else { return }
      do {
        let page = try await self.fetchPage(cursor: cursor)
        await MainActor.run {
          guard self.isViewLoaded else { return }
          let values = self.presentations(from: page)
          self.contacts = replacing ? values : self.merging(values, into: self.contacts)
          self.filteredContacts = self.contacts
          self.nextCursor = page.nextCursor
          self.hasMore = page.hasMore
          self.isLoading = false
          self.refreshControl?.endRefreshing()
        }
      } catch {
        await MainActor.run {
          self.isLoading = false
          self.refreshControl?.endRefreshing()
          self.onLoadError?(error, self)
        }
      }
    }
  }
  /** Converts an SDK cursor page to UIKit rows. Subclasses can add remote avatar loading or display metadata. */
  open func presentations(from page: PteIMUIContactPage) -> [PteIMUIContactPresentation] {
    page.items.map { item in
      PteIMUIContactPresentation(identifier: item.identifier, kind: item.kind, title: item.title, subtitle: item.subtitle, avatarText: PteIMUIMessageText.avatarText(for: item.title))
    }
  }
  open func configure(cell: PteIMUIContactCell, presentation: PteIMUIContactPresentation, at indexPath: IndexPath) { cell.configure(presentation: presentation, style: skin.list, palette: skin.theme.palette(for: traitCollection), icons: skin.icons) }
  /** Override these hooks to replace contact cells while retaining paging, search and chat routing. */
  open func registerContactCells(in tableView: UITableView) {
    tableView.register(PteIMUIContactCell.self, forCellReuseIdentifier: PteIMUIContactCell.contactReuseIdentifier)
  }
  open func contactCellReuseIdentifier(for presentation: PteIMUIContactPresentation) -> String {
    PteIMUIContactCell.contactReuseIdentifier
  }
  open func configure(cell: UITableViewCell, presentation: PteIMUIContactPresentation, at indexPath: IndexPath) {
    (cell as? PteIMUIContactCell).map { configure(cell: $0, presentation: presentation, at: indexPath) }
  }
  open func didTapAvatar(_ contact: PteIMUIContactPresentation) { onAvatarTapped?(contact, self) }
  open func didSelectContact(_ contact: PteIMUIContactPresentation) {
    if let onContactSelected { onContactSelected(contact, self); return }
    navigationController?.pushViewController(makeChatViewController(for: contact), animated: true)
  }
  open func makeChatViewController(for contact: PteIMUIContactPresentation) -> PteIMUIChatViewController {
    let chat = PteIMUIChatViewController(client: client, conversationId: contact.identifier, title: contact.title, skin: skin)
    chat.showsIncomingSenderNames = contact.kind == .group
    return chat
  }
  private func bindClient() {
    listener.onThemeModeChanged = { [weak self] _ in DispatchQueue.main.async { self?.appearanceController.refresh() } }
    listener.onLanguageChanged = { [weak self] _ in DispatchQueue.main.async {
      guard let self else { return }
      self.title = Self.title(for: self.mode, language: self.client.resolvedLanguage())
      self.applySkin()
    } }
    client.addListener(listener)
  }
  private func applySkin() {
    guard isViewLoaded else { return }
    let palette = skin.theme.palette(for: traitCollection)
    // UITableViewController uses the table itself behind the safe area. Keep
    // that status-bar region identical to the fixed top navigation surface.
    tableView.backgroundColor = palette.surfaceColor; tableView.rowHeight = skin.list.rowHeight; refreshControl?.tintColor = palette.outgoingGradientStartColor
    chrome.apply(palette: palette, title: title ?? "Contacts", language: client.appearance.language, icons: skin.icons)
    layoutChromeIfNeeded(force: true)
    if filteredContacts.isEmpty { filteredContacts = contacts }
    tableView.reloadData()
  }
  open override func traitCollectionDidChange(_ previous: UITraitCollection?) { super.traitCollectionDidChange(previous); if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { applySkin() } }
  open override func numberOfSections(in tableView: UITableView) -> Int { contactSections.count }
  open override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { contactSections[section].values.count }
  open override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let contact = contactSections[indexPath.section].values[indexPath.row]
    let cell = tableView.dequeueReusableCell(withIdentifier: contactCellReuseIdentifier(for: contact), for: indexPath)
    configure(cell: cell, presentation: contact, at: indexPath)
    (cell as? PteIMUIContactCell)?.onAvatarTapped = { [weak self] in self?.didTapAvatar(contact) }
    return cell
  }
  open override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); didSelectContact(contactSections[indexPath.section].values[indexPath.row]) }
  open override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { contactSections[section].title == nil ? 0.01 : 28 }
  open override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    guard let title = contactSections[section].title else { return nil }
    let header = UIView(); header.backgroundColor = skin.theme.palette(for: traitCollection).backgroundColor
    let label = UILabel(); label.translatesAutoresizingMaskIntoConstraints = false; label.text = title.uppercased(); label.font = .systemFont(ofSize: 10, weight: .semibold); label.textColor = skin.theme.palette(for: traitCollection).secondaryTextColor; label.setContentHuggingPriority(.required, for: .vertical); header.addSubview(label)
    NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: skin.list.horizontalInset), label.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -skin.list.horizontalInset), label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -5)])
    return header
  }
  open override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    guard indexPath.section == contactSections.count - 1, indexPath.row == contactSections[indexPath.section].values.count - 1 else { return }
    loadNextPage()
  }

  private func fetchPage(cursor: String) async throws -> PteIMUIContactPage {
    switch mode {
    case .friends:
      let page = try await client.fetchFriends(cursor: cursor)
      return PteIMUIContactPage(items: page.list.map { contact in
        let title = contact.remark.isEmpty ? (contact.nickname.isEmpty ? contact.userId : contact.nickname) : contact.remark
        return PteIMUIContactItem(identifier: contact.userId, kind: .single, title: title, subtitle: contact.remark.isEmpty ? nil : contact.nickname)
      }, nextCursor: page.nextCursor, hasMore: page.hasMore)
    case .follows:
      let page = try await client.fetchFollows(cursor: cursor)
      return PteIMUIContactPage(items: page.list.map { contact in
        let title = contact.remark.isEmpty ? (contact.nickname.isEmpty ? contact.userId : contact.nickname) : contact.remark
        return PteIMUIContactItem(identifier: contact.userId, kind: .single, title: title, subtitle: contact.remark.isEmpty ? nil : contact.nickname)
      }, nextCursor: page.nextCursor, hasMore: page.hasMore)
    case .groups:
      let page = try await client.fetchGroups(cursor: cursor)
      return PteIMUIContactPage(items: page.list.map { group in
        PteIMUIContactItem(identifier: String(group.id), kind: .group, title: group.title.isEmpty ? String(group.id) : group.title, subtitle: nil)
      }, nextCursor: page.nextCursor, hasMore: page.hasMore)
    case .custom:
      return PteIMUIContactPage(items: [], nextCursor: "", hasMore: false)
    }
  }
  private func merging(_ additions: [PteIMUIContactPresentation], into current: [PteIMUIContactPresentation]) -> [PteIMUIContactPresentation] {
    additions.reduce(into: current) { result, value in if let index = result.firstIndex(where: { $0.identifier == value.identifier && $0.kind == value.kind }) { result[index] = value } else { result.append(value) } }
  }
  private func filterContacts(_ query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    filteredContacts = trimmed.isEmpty ? contacts : contacts.filter { $0.title.localizedCaseInsensitiveContains(trimmed) || ($0.subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false) }
    tableView.reloadData()
  }
  private func layoutChromeIfNeeded(force: Bool = false) {
    // Uses the same 44pt title row as Conversations.  Only the optional
    // search/action content beneath that row changes the header height.
    let size = CGSize(width: tableView.bounds.width, height: chrome.preferredHeight)
    guard force || chrome.frame.size != size else { return }
    chrome.frame = CGRect(origin: .zero, size: size)
    tableView.tableHeaderView = chrome
  }
  private static func title(for mode: PteIMUIContactListMode, language: PteIMLanguage) -> String {
    switch mode { case .friends: return PteIMUILocalization.value("好友", "Friends", language: language); case .follows: return PteIMUILocalization.value("关注", "Following", language: language); case .groups: return PteIMUILocalization.value("群组", "Groups", language: language); case .custom: return PteIMUILocalization.value("联系人", "Contacts", language: language) }
  }
}

/** Normalised page keeps the UIKit extension API independent from Core transport structs. */
public struct PteIMUIContactPage {
  public let items: [PteIMUIContactItem]
  public let nextCursor: String
  public let hasMore: Bool
  public init(items: [PteIMUIContactItem], nextCursor: String, hasMore: Bool) { self.items = items; self.nextCursor = nextCursor; self.hasMore = hasMore }
}

public struct PteIMUIContactItem {
  public let identifier: String
  public let kind: PteIMUIConversationKind
  public let title: String
  public let subtitle: String?
  public init(identifier: String, kind: PteIMUIConversationKind, title: String, subtitle: String? = nil) { self.identifier = identifier; self.kind = kind; self.title = title; self.subtitle = subtitle }
}

open class PteIMUIContactCell: PteIMUIConversationCell {
  public static let contactReuseIdentifier = "PteIMUIContactCell"
  private let presenceDot = UIView()
  public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    presenceDot.translatesAutoresizingMaskIntoConstraints = false; presenceDot.layer.cornerRadius = 5; presenceDot.isHidden = true; contentView.addSubview(presenceDot)
    NSLayoutConstraint.activate([presenceDot.widthAnchor.constraint(equalToConstant: 10), presenceDot.heightAnchor.constraint(equalTo: presenceDot.widthAnchor), presenceDot.trailingAnchor.constraint(equalTo: avatarButton.trailingAnchor, constant: 1), presenceDot.bottomAnchor.constraint(equalTo: avatarButton.bottomAnchor, constant: 1)])
  }
  required public init?(coder: NSCoder) { nil }
  open func configure(presentation: PteIMUIContactPresentation, style: PteIMUIListStyle, palette: PteIMUIThemePalette, icons: PteIMUIIconProvider = PteIMUISystemIconProvider()) {
    super.configure(presentation: PteIMUIConversationPresentation(conversationId: presentation.identifier, kind: presentation.kind, title: presentation.title, subtitle: presentation.subtitle, avatarText: presentation.avatarText, avatarImage: presentation.avatarImage, avatarBackgroundColor: presentation.avatarBackgroundColor), style: style, palette: palette, icons: icons)
    timeLabel.isHidden = true; unreadLabel.isHidden = true
    presenceDot.isHidden = !presentation.isOnline; presenceDot.backgroundColor = style.presenceOnlineColor; presenceDot.layer.borderColor = (style.presenceBorderColor ?? palette.backgroundColor).cgColor; presenceDot.layer.borderWidth = 2
  }
}
