import UIKit
import PteIMUIKit

/** The demo owns only runtime login; chat UI itself comes from the PteIMUIKit package. */
final class PteIMUIDemoViewController: UIViewController {
  private let apiDomain = PteIMUIDemoViewController.field("https://api.example.com", "API domain")
  private let imDomain = PteIMUIDemoViewController.field("wss://im.example.com/ws", "IM WSS URL")
  private let cosDomain = PteIMUIDemoViewController.field("https://cos.example.com", "COS domain")
  private let appId = PteIMUIDemoViewController.field("1400000001", "SDK App ID", keyboard: .numberPad)
  private let userId = PteIMUIDemoViewController.field("10001", "Numeric user ID", keyboard: .numberPad)
  private let userSig = PteIMUIDemoViewController.field("", "UserSig from your backend", secure: true)
  private let conversationId = PteIMUIDemoViewController.field("c2c:10001:10002", "Conversation ID")
  private let status = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad(); title = "PteIMUIKit Demo"; view.backgroundColor = .systemBackground
    let note = UILabel(); note.text = "此页面仅用于运行时登录。聊天 UI 来自 PteIMUIKit，所有参数不会写入磁盘。"; note.numberOfLines = 0; note.font = .preferredFont(forTextStyle: .footnote); note.textColor = .secondaryLabel
    status.font = .preferredFont(forTextStyle: .footnote); status.textColor = .systemBlue; status.text = "未连接"
    let connect = UIButton(type: .system); connect.setTitle("进入 PteIMUIKit 聊天", for: .normal); connect.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [note, apiDomain, imDomain, cosDomain, appId, userId, userSig, conversationId, connect, status]); stack.axis = .vertical; stack.spacing = 12
    view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)])
  }
  @objc private func connectTapped() {
    do {
      let base = try PteIMBaseConfig(apiDomain: apiDomain.text ?? "", imDomain: imDomain.text ?? "", cosDomain: cosDomain.text ?? "", themeMode: .system, language: .zhCN)
      let login = try PteIMLoginConfig(sdkAppId: Int64(appId.text ?? "") ?? 0, userId: userId.text ?? "", userSig: userSig.text ?? "")
      let client = try PteLiveIM.configure(base).login(login)
      let chat = PteIMUIKit.makeChatViewController(client: client, conversationId: conversationId.text ?? "", title: "PteIMUIKit")
      chat.onActionRequested = { action, controller in
        let alert = UIAlertController(title: action.title(language: client.appearance.language), message: "请由宿主 App 接入系统选择器或业务流程，然后调用 PteIMUIChatViewController 对应的 send 方法。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default)); controller.present(alert, animated: true)
      }
      navigationController?.pushViewController(chat, animated: true)
    } catch { status.text = "配置错误：\(error.localizedDescription)" }
  }
  private static func field(_ value: String, _ placeholder: String, keyboard: UIKeyboardType = .default, secure: Bool = false) -> UITextField { let field = UITextField(); field.text = value; field.placeholder = placeholder; field.borderStyle = .roundedRect; field.keyboardType = keyboard; field.isSecureTextEntry = secure; field.autocapitalizationType = .none; return field }
}
