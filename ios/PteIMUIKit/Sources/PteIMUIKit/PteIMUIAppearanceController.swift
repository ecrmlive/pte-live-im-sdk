import UIKit
import PteIMSDK

/**
 Keeps a UIKit surface in sync with the SDK's resolved appearance. Automatic
 mode is re-evaluated at 07:00 and 19:00, and again after foreground or a
 significant device-time change.
 */
@MainActor final class PteIMUIAppearanceController {
  private weak var viewController: UIViewController?
  private let client: PteIMSDK
  private var notificationTokens: [NSObjectProtocol] = []
  private var transitionTimer: Timer?

  init(client: PteIMSDK, viewController: UIViewController) {
    self.client = client
    self.viewController = viewController
  }

  isolated deinit {
    transitionTimer?.invalidate()
    notificationTokens.forEach(NotificationCenter.default.removeObserver)
  }

  func start() {
    guard notificationTokens.isEmpty else { refresh() ; return }
    let center = NotificationCenter.default
    [UIApplication.willEnterForegroundNotification, UIApplication.significantTimeChangeNotification, NSLocale.currentLocaleDidChangeNotification].forEach { name in
      notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.refresh() }
      })
    }
    refresh()
  }

  func refresh() {
    guard let viewController else { return }
    viewController.overrideUserInterfaceStyle = client.resolvedTheme() == .dark ? .dark : .light
    scheduleNextAutomaticTransition()
  }

  private func scheduleNextAutomaticTransition() {
    transitionTimer?.invalidate()
    transitionTimer = nil
    guard client.appearance.themeMode == .system else { return }

    let calendar = Calendar.current
    let now = Date()
    let morning = calendar.nextDate(after: now, matching: DateComponents(hour: 7, minute: 0, second: 0), matchingPolicy: .nextTime)
    let evening = calendar.nextDate(after: now, matching: DateComponents(hour: 19, minute: 0, second: 0), matchingPolicy: .nextTime)
    guard let next = [morning, evening].compactMap({ $0 }).min() else { return }
    transitionTimer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
    RunLoop.main.add(transitionTimer!, forMode: .common)
  }
}
