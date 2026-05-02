import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Fonts are auto-registered from Info.plist's UIAppFonts — no manual
        // CTFontManagerRegisterFontsForURL needed, and doing both causes
        // "file already registered" faults.

        // Kick off entitlement verification against StoreKit on every launch.
        // This is the authoritative source for the IAP flag; the UserDefaults
        // cache is only used for the first frame before this completes.
        Task { @MainActor in
            await IAPManager.shared.bootstrap()
        }

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = GameViewController()
        window?.makeKeyAndVisible()
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return .portrait
    }
}
