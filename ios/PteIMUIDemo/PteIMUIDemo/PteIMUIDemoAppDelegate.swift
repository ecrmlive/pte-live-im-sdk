import UIKit
import PteIMSDK

@main
final class PteIMUIDemoAppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var applicationSession: PteIMUIDemoApplicationSession?
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    // Paint the root window during the launch-to-login handoff. This prevents
    // an uncoloured navigation container from exposing black bands.
    window.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 1.00, alpha: 1)
    let splash = PteIMUIDemoLaunchViewController()
    splash.modalPresentationStyle = .fullScreen
    window.rootViewController = splash
    window.makeKeyAndVisible(); self.window = window
    do {
      // Application-level configuration happens once, before any user sees a
      // login screen. Domains are never user-login form fields.
      let session = try PteIMUIDemoApplicationSession()
      applicationSession = session
      #if DEBUG
      let launchDuration: TimeInterval = ProcessInfo.processInfo.arguments.contains("--pte-im-ui-preview-launch") ? 5 : 0.9
      #else
      let launchDuration: TimeInterval = 0.9
      #endif
      DispatchQueue.main.asyncAfter(deadline: .now() + launchDuration) { [weak self] in
        guard let self, let session = self.applicationSession else { return }
        let home = UINavigationController(rootViewController: PteIMUIDemoViewController(applicationSession: session))
        home.view.backgroundColor = self.window?.backgroundColor
        home.setNavigationBarHidden(true, animated: false)
        home.modalPresentationStyle = .fullScreen
        guard let window = self.window else { return }
        UIView.transition(with: window, duration: 0.24, options: .transitionCrossDissolve) {
          window.rootViewController = home
        }
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
    #if DEBUG
    // The iOS Simulator shares localhost with the development Mac. Keeping
    // these values in Info-Debug.plist makes the local endpoint explicit.
    let apiDomain = Bundle.main.object(forInfoDictionaryKey: "PTEIMDebugAPIDomain") as? String ?? "http://127.0.0.1:11504"
    let imDomain = Bundle.main.object(forInfoDictionaryKey: "PTEIMDebugIMDomain") as? String ?? "ws://127.0.0.1:11510/ws"
    let cosDomain = Bundle.main.object(forInfoDictionaryKey: "PTEIMDebugCOSDomain") as? String ?? "http://127.0.0.1:9000"
    baseConfig = try PteIMBaseConfig(
      apiDomain: apiDomain,
      imDomain: imDomain,
      cosDomain: cosDomain,
      commerceDomain: nil,
      themeMode: .system,
      language: .system,
      allowInsecureLocalhost: true
    )
    #else
    // Release uses SDK public defaults; hosts override any field as needed.
    baseConfig = try PteIMBaseConfig(themeMode: .system, language: .system)
    #endif
    bootstrap = PteIMSDK.configure(baseConfig)
  }
}

/** Branded launch view. The system launch screen stays immediate; this view provides the product transition. */
private final class PteIMUIDemoLaunchViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.04, green: 0.02, blue: 0.15, alpha: 1)
    if let background = UIImage(named: "PteIMUILaunchBackground") {
      let imageView = UIImageView(image: background); imageView.contentMode = .scaleAspectFill; imageView.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(imageView)
      NSLayoutConstraint.activate([imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor), imageView.topAnchor.constraint(equalTo: view.topAnchor), imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    // This cut already contains the complete startup composition: background,
    // logo, title, English caption and decorative nodes. Do not recreate or
    // scale individual elements in code.
    let artwork = UIImageView(image: UIImage(named: "PteIMUILaunchMark"))
    artwork.contentMode = .scaleAspectFill
    artwork.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(artwork)
    NSLayoutConstraint.activate([
      artwork.leadingAnchor.constraint(equalTo: view.leadingAnchor), artwork.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      artwork.topAnchor.constraint(equalTo: view.topAnchor), artwork.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }
  func showConfigurationError(_ message: String) {
    let label = UILabel(); label.text = "PteIMBaseConfig 初始化失败\n\(message)"; label.textColor = .white; label.textAlignment = .center; label.numberOfLines = 0; label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
    NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor), label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor), label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30)])
  }
}
