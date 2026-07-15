import UIKit
import PteIMSDK

@main
final class PteIMUIDemoAppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var applicationSession: PteIMUIDemoApplicationSession?
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    let splash = PteIMUIDemoLaunchViewController()
    window.rootViewController = splash
    window.makeKeyAndVisible(); self.window = window
    do {
      // Application-level configuration happens once, before any user sees a
      // login screen. Domains are never user-login form fields.
      let session = try PteIMUIDemoApplicationSession()
      applicationSession = session
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
        guard let self, let session = self.applicationSession else { return }
        let home = UINavigationController(rootViewController: PteIMUIDemoViewController(applicationSession: session))
        home.modalTransitionStyle = .crossDissolve
        self.window?.rootViewController = home
      }
    } catch {
      splash.showConfigurationError(error.localizedDescription)
    }
    return true
  }
}

/** App-scoped configuration and Core bootstrap. Login credentials are deliberately absent here. */
final class PteIMUIDemoApplicationSession {
  let baseConfig: PteIMBaseConfig
  let bootstrap: PteIMSDKBootstrap
  init() throws {
    baseConfig = try PteIMBaseConfig(
      apiDomain: "https://api-im.ptelive.com",
      imDomain: "wss://wss.ptelive.com/ws",
      cosDomain: "https://cos.ptelive.com",
      themeMode: .system,
      language: .zhCN
    )
    bootstrap = PteIMSDK.configure(baseConfig)
  }
}

/** Branded launch view. The system launch screen stays immediate; this view provides the product transition. */
private final class PteIMUIDemoLaunchViewController: UIViewController {
  private let gradient = CAGradientLayer()
  override func viewDidLoad() {
    super.viewDidLoad()
    gradient.colors = [UIColor(red: 0.04, green: 0.17, blue: 0.52, alpha: 1).cgColor, UIColor(red: 0.16, green: 0.38, blue: 0.96, alpha: 1).cgColor, UIColor(red: 0.43, green: 0.18, blue: 0.88, alpha: 1).cgColor]
    gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1); view.layer.insertSublayer(gradient, at: 0)
    let mark = UIView(); mark.backgroundColor = UIColor.white.withAlphaComponent(0.16); mark.layer.cornerRadius = 46; mark.layer.borderWidth = 1; mark.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
    let mic = UIImageView(image: UIImage(systemName: "mic.fill")); mic.tintColor = .white; mic.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 43, weight: .medium)
    let title = UILabel(); title.text = "Pte Live IM"; title.textColor = .white; title.font = .systemFont(ofSize: 25, weight: .bold)
    let caption = UILabel(); caption.text = "PRIVATE LIVE · SECURE MESSAGING"; caption.textColor = UIColor.white.withAlphaComponent(0.72); caption.font = .systemFont(ofSize: 11, weight: .semibold)
    [mark, mic, title, caption].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    NSLayoutConstraint.activate([
      mark.centerXAnchor.constraint(equalTo: view.centerXAnchor), mark.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -36), mark.widthAnchor.constraint(equalToConstant: 92), mark.heightAnchor.constraint(equalToConstant: 92),
      mic.centerXAnchor.constraint(equalTo: mark.centerXAnchor), mic.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
      title.centerXAnchor.constraint(equalTo: view.centerXAnchor), title.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: 22),
      caption.centerXAnchor.constraint(equalTo: view.centerXAnchor), caption.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8)
    ])
  }
  override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); gradient.frame = view.bounds }
  func showConfigurationError(_ message: String) {
    let label = UILabel(); label.text = "PteIMBaseConfig 初始化失败\n\(message)"; label.textColor = .white; label.textAlignment = .center; label.numberOfLines = 0; label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
    NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor), label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor), label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30)])
  }
}
