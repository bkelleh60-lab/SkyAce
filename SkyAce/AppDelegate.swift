import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Fonts are auto-registered from Info.plist's UIAppFonts — no manual
        // CTFontManagerRegisterFontsForURL needed, and doing both causes
        // "file already registered" faults.

        // Window + root view controller setup moved to `SceneDelegate` under
        // the UIScene lifecycle (SKY-98). The scene configuration is declared
        // in Info.plist's UIApplicationSceneManifest.
        return true
    }

    // Still consulted for orientation under the scene lifecycle. iPhone stays
    // portrait-only; iPad supports all orientations (SKY-98) — Apple now warns
    // when an iPad app doesn't, so restricting orientations to block Split View
    // / Slide Over would only trade one deprecation fault for another.
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return .portrait
    }
}
