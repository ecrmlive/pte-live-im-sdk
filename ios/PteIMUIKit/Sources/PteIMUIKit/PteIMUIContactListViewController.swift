import UIKit
import PteIMSDK

/**
 Business-directory driven contact list. PteIMSDK deliberately does not own
 friend relations, so hosts provide contacts through [contacts] or override
 [reloadContacts]. Both one-to-one and group rows route through open hooks.
 */
open class PteIMUIContactListViewController: UITableViewController {
  public let client: PteIMSDK
  public var skin: PteIMUISkin { didSet { applySkin() } }
  public var contacts: [PteIMUIContactPresentation] = [] { didSet { if isViewLoaded { tableView.reloadData() } } }
  public var onAvatarTapped: ((PteIMUIContactPresentation, PteIMUIContactListViewController) -> Void)?
  public var onContactSelected: ((PteIMUIContactPresentation, PteIMUIContactListViewController) -> Void)?

  public init(client: PteIMSDK, skin: PteIMUISkin = .default) {
    self.client = client; self.skin = skin; super.init(style: .plain)
    title = PteIMUILocalization.value("联系人", "Contacts", language: client.appearance.language)
  }
  required public init?(coder: NSCoder) { nil }
  open override func viewDidLoad() {
    super.viewDidLoad(); tableView.register(PteIMUIContactCell.self, forCellReuseIdentifier: PteIMUIContactCell.contactReuseIdentifier); tableView.separatorStyle = .none
    refreshControl = UIRefreshControl(); refreshControl?.addTarget(self, action: #selector(reloadContacts), for: .valueChanged); applySkin()
  }
  @objc open func reloadContacts() { refreshControl?.endRefreshing(); tableView.reloadData() }
  open func configure(cell: PteIMUIContactCell, presentation: PteIMUIContactPresentation, at indexPath: IndexPath) { cell.configure(presentation: presentation, style: skin.list, palette: skin.theme.palette(for: traitCollection), icons: skin.icons) }
  open func didTapAvatar(_ contact: PteIMUIContactPresentation) { onAvatarTapped?(contact, self) }
  open func didSelectContact(_ contact: PteIMUIContactPresentation) {
    if let onContactSelected { onContactSelected(contact, self); return }
    navigationController?.pushViewController(makeChatViewController(for: contact), animated: true)
  }
  open func makeChatViewController(for contact: PteIMUIContactPresentation) -> PteIMUIChatViewController {
    PteIMUIChatViewController(client: client, conversationId: contact.identifier, title: contact.title, skin: skin)
  }
  private func applySkin() { guard isViewLoaded else { return }; let palette = skin.theme.palette(for: traitCollection); tableView.backgroundColor = palette.backgroundColor; tableView.rowHeight = skin.list.rowHeight; refreshControl?.tintColor = palette.outgoingGradientStartColor; tableView.reloadData() }
  open override func traitCollectionDidChange(_ previous: UITraitCollection?) { super.traitCollectionDidChange(previous); if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { applySkin() } }
  open override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { contacts.count }
  open override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: PteIMUIContactCell.contactReuseIdentifier, for: indexPath) as! PteIMUIContactCell
    let contact = contacts[indexPath.row]; configure(cell: cell, presentation: contact, at: indexPath); cell.onAvatarTapped = { [weak self] in self?.didTapAvatar(contact) }; return cell
  }
  open override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); didSelectContact(contacts[indexPath.row]) }
}

open class PteIMUIContactCell: PteIMUIConversationCell {
  public static let contactReuseIdentifier = "PteIMUIContactCell"
  open func configure(presentation: PteIMUIContactPresentation, style: PteIMUIListStyle, palette: PteIMUIThemePalette, icons: PteIMUIIconProvider = PteIMUISystemIconProvider()) {
    super.configure(presentation: PteIMUIConversationPresentation(conversationId: presentation.identifier, kind: presentation.kind, title: presentation.title, subtitle: presentation.subtitle, avatarText: presentation.avatarText, avatarImage: presentation.avatarImage), style: style, palette: palette, icons: icons)
    timeLabel.isHidden = true; unreadLabel.isHidden = true
  }
}
