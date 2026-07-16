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
  private var filteredContacts: [PteIMUIContactPresentation] = []

  public init(client: PteIMSDK, mode: PteIMUIContactListMode = .friends, skin: PteIMUISkin = .default) {
    self.client = client; self.mode = mode; self.skin = skin; super.init(style: .plain)
    title = Self.title(for: mode, language: client.appearance.language)
  }
  required public init?(coder: NSCoder) { nil }
  open override func viewDidLoad() {
    super.viewDidLoad(); tableView.register(PteIMUIContactCell.self, forCellReuseIdentifier: PteIMUIContactCell.contactReuseIdentifier); tableView.separatorStyle = .none
    tableView.tableHeaderView = chrome
    chrome.onSearchChanged = { [weak self] query in self?.filterContacts(query) }
    chrome.onAddTapped = { [weak self] in guard let self else { return }; self.onAddRequested?(self) }
    chrome.onAppearanceTapped = { [weak self] in self?.toggleAppearance() }
    chrome.onLanguageTapped = { [weak self] in self?.toggleLanguage() }
    refreshControl = UIRefreshControl(); refreshControl?.addTarget(self, action: #selector(reloadContacts), for: .valueChanged); applySkin(); reloadContacts()
  }
  open override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
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
  open func didTapAvatar(_ contact: PteIMUIContactPresentation) { onAvatarTapped?(contact, self) }
  open func didSelectContact(_ contact: PteIMUIContactPresentation) {
    if let onContactSelected { onContactSelected(contact, self); return }
    navigationController?.pushViewController(makeChatViewController(for: contact), animated: true)
  }
  open func makeChatViewController(for contact: PteIMUIContactPresentation) -> PteIMUIChatViewController {
    PteIMUIChatViewController(client: client, conversationId: contact.identifier, title: contact.title, skin: skin)
  }
  private func applySkin() {
    guard isViewLoaded else { return }
    let palette = skin.theme.palette(for: traitCollection)
    tableView.backgroundColor = palette.backgroundColor; tableView.rowHeight = skin.list.rowHeight; refreshControl?.tintColor = palette.outgoingGradientStartColor
    chrome.apply(palette: palette, title: title ?? "Contacts", language: client.appearance.language)
    layoutChromeIfNeeded(force: true)
    if filteredContacts.isEmpty { filteredContacts = contacts }
    tableView.reloadData()
  }
  open override func traitCollectionDidChange(_ previous: UITraitCollection?) { super.traitCollectionDidChange(previous); if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { applySkin() } }
  open override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filteredContacts.count }
  open override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: PteIMUIContactCell.contactReuseIdentifier, for: indexPath) as! PteIMUIContactCell
    let contact = filteredContacts[indexPath.row]; configure(cell: cell, presentation: contact, at: indexPath); cell.onAvatarTapped = { [weak self] in self?.didTapAvatar(contact) }; return cell
  }
  open override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); didSelectContact(filteredContacts[indexPath.row]) }
  open override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
    guard indexPath.row == filteredContacts.count - 1 else { return }
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
    let size = CGSize(width: tableView.bounds.width, height: 180)
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
    applySkin()
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
  open func configure(presentation: PteIMUIContactPresentation, style: PteIMUIListStyle, palette: PteIMUIThemePalette, icons: PteIMUIIconProvider = PteIMUISystemIconProvider()) {
    super.configure(presentation: PteIMUIConversationPresentation(conversationId: presentation.identifier, kind: presentation.kind, title: presentation.title, subtitle: presentation.subtitle, avatarText: presentation.avatarText, avatarImage: presentation.avatarImage, avatarBackgroundColor: presentation.avatarBackgroundColor), style: style, palette: palette, icons: icons)
    timeLabel.isHidden = true; unreadLabel.isHidden = true
  }
}
