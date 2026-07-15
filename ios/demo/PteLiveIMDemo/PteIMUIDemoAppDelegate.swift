import UIKit

@main
final class PteIMUIDemoAppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = UINavigationController(rootViewController: PteIMUIDemoViewController())
    window.makeKeyAndVisible(); self.window = window
    return true
  }
}
