import UIKit
import PteLiveIM

/** Cache-first conversation list that refreshes whenever the Core SDK emits a message. */
public final class PteIMUIConversationListViewController: UITableViewController {
  public let client: PteLiveIM
  public var theme: PteIMUITheme { didSet { applyTheme() } }
  public var onConversationSelected: ((PteIMConversation, PteIMUIConversationListViewController) -> Void)?
  private var conversations: [PteIMConversation] = []
  private var previousMessageCallback: ((PteIMMessage) -> Void)?

  public init(client: PteLiveIM, theme: PteIMUITheme = .default) { self.client = client; self.theme = theme; super.init(style: .plain); title = "消息" }
  required init?(coder: NSCoder) { nil }
  public override func viewDidLoad() { super.viewDidLoad(); tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PteIMUIConversationCell"); refreshControl = UIRefreshControl(); refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged); bindClient(); reloadConversations(); applyTheme() }
  // The chained callback captures this controller weakly; do not overwrite callbacks installed by the host later.
  @objc public func refresh() { client.syncNow(); reloadConversations(); refreshControl?.endRefreshing() }
  public func reloadConversations() { conversations = (try? client.localConversations(limit: 100)) ?? []; tableView.reloadData() }
  private func bindClient() { previousMessageCallback = client.onMessage; client.onMessage = { [weak self] message in self?.previousMessageCallback?(message); DispatchQueue.main.async { self?.reloadConversations() } } }
  private func applyTheme() { guard isViewLoaded else { return }; tableView.backgroundColor = theme.backgroundColor; tableView.reloadData() }
  public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { conversations.count }
  public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let cell = tableView.dequeueReusableCell(withIdentifier: "PteIMUIConversationCell", for: indexPath); let conversation = conversations[indexPath.row]; var content = cell.defaultContentConfiguration(); content.text = conversation.conversationId; content.secondaryText = PteIMUIMessageText.render(conversation.lastMessage); content.textProperties.color = theme.primaryTextColor; content.secondaryTextProperties.color = theme.secondaryTextColor; cell.contentConfiguration = content; cell.backgroundColor = theme.backgroundColor; return cell }
  public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { let conversation = conversations[indexPath.row]; if let onConversationSelected { onConversationSelected(conversation, self) } else { navigationController?.pushViewController(PteIMUIKit.makeChatViewController(client: client, conversationId: conversation.conversationId, title: conversation.conversationId, theme: theme), animated: true) } }
}
