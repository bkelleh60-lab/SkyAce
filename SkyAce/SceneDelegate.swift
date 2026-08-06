import UIKit

/// Owns the app's single window under the UIScene lifecycle. Window + root
/// view controller setup lived in `AppDelegate` before SKY-98; it now happens
/// here so UIKit runs the modern scene path (the legacy AppDelegate window
/// path logs a "UIScene lifecycle will soon be required" fault).
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
