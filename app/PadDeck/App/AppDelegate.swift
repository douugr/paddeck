import UIKit
import SwiftUI
import Combine

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Prefs.registerDefaults()
        _ = Connection.shared   // starts the USB listener
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.overrideUserInterfaceStyle = .dark
        w.tintColor = Theme.accent
        w.rootViewController = RootViewController()
        w.makeKeyAndVisible()
        window = w
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Connection.shared.resume()
    }
}

/// Shows the connect screen or the main screen depending on the connection.
final class RootViewController: UIViewController {
    private var current: UIViewController?
    private var subs = Set<AnyCancellable>()

    override var childForStatusBarStyle: UIViewController? { current }
    override var childForHomeIndicatorAutoHidden: UIViewController? { current }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        show(UIHostingController(rootView: ConnectView()), animated: false)
        Connection.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(state) }
            .store(in: &subs)
    }

    private func update(_ state: Connection.State) {
        let onMain = current is MainViewController
        if state == .connected && !onMain {
            show(MainViewController(), animated: true)
        } else if state == .idle && onMain {
            show(UIHostingController(rootView: ConnectView()), animated: true)
        }
    }

    private func show(_ vc: UIViewController, animated: Bool) {
        let old = current
        old?.presentedViewController?.dismiss(animated: false)
        addChild(vc)
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(vc.view)
        vc.didMove(toParent: self)
        current = vc
        setNeedsStatusBarAppearanceUpdate()

        guard let old = old else { return }
        old.willMove(toParent: nil)
        let finish = {
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        if animated {
            vc.view.alpha = 0
            UIView.animate(withDuration: 0.25, animations: { vc.view.alpha = 1 }, completion: { _ in finish() })
        } else {
            finish()
        }
    }
}
