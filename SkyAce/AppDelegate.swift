import UIKit
import CoreText

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Register bundled TTFs for SpriteKit/UIKit label use.
        registerBundledFonts()

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
        return .portrait
    }

    // MARK: - Font registration

    /// Load TTF files from the app bundle. Fonts that aren't present (e.g.
    /// during early development) are silently skipped; SkyFonts falls back
    /// to system fonts in that case.
    private func registerBundledFonts() {
        let candidates = [
            ("PlusJakartaSans-Bold",            "ttf"),
            ("PlusJakartaSans-ExtraBold",       "ttf"),
            ("PlusJakartaSans-ExtraBoldItalic", "ttf"),
            ("BeVietnamPro-Regular",            "ttf"),
            ("BeVietnamPro-Medium",             "ttf")
        ]
        for (name, ext) in candidates {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
