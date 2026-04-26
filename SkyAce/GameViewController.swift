import UIKit
import SpriteKit

/// Hosts an SKView that presents the current SKScene. All scene transitions
/// go through `SkyNavigator`.
final class GameViewController: UIViewController {

    private var skView: SKView!

    override func loadView() {
        let view = SKView(frame: UIScreen.main.bounds)
        view.backgroundColor = SkyColors.surface
        // Render siblings in add-order. Our UI composites (bento tiles, tab
        // bar buttons, coin pill, etc.) stack background/icon/label at the
        // same zPosition — with sibling order ignored, SpriteKit occasionally
        // drew the label beneath its background, producing blank buttons.
        view.ignoresSiblingOrder = false
        // Performance overlays — disabled for shipping builds.
        #if DEBUG
        view.showsFPS = false
        view.showsNodeCount = false
        #endif
        self.skView = view
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        SkyNavigator.shared.attach(view: skView, presenter: self)
        SkyNavigator.shared.showMenu()
        AudioManager.shared.playMusic(SkyMusic.menu, fileExtension: "wav")
        #if DEBUG
        installDebugUnlockBanner()
        #endif
    }

    #if DEBUG
    /// Persistent red badge shown on top of the SKView whenever the IAP
    /// paywall is being bypassed via `debugUnlockAllContent` (DebugConfig.swift).
    /// Stripped from Release builds — `#if DEBUG` excludes the entire helper
    /// and its caller in `viewDidLoad`.
    private func installDebugUnlockBanner() {
        guard debugUnlockAllContent else { return }

        let banner = UILabel()
        banner.text = "DEBUG: All Unlocked"
        banner.textColor = .white
        banner.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        banner.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        banner.textAlignment = .center
        banner.layer.cornerRadius = 6
        banner.layer.masksToBounds = true
        banner.isUserInteractionEnabled = false
        banner.accessibilityIdentifier = "DebugUnlockBanner"
        banner.translatesAutoresizingMaskIntoConstraints = false

        skView.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: skView.safeAreaLayoutGuide.topAnchor, constant: 6),
            banner.trailingAnchor.constraint(equalTo: skView.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            banner.heightAnchor.constraint(equalToConstant: 20),
            banner.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
        // UILabel has no horizontal padding by default — pad the text via
        // a small inset on either side using attributed string spacing.
        banner.text = "  DEBUG: All Unlocked  "
    }
    #endif

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    /// Presents the parental gate modally before running a successful closure.
    /// Used before every IAP purchase attempt.
    func presentParentalGate(onSuccess: @escaping () -> Void) {
        let gate = ParentalGateViewController()
        gate.onSuccess = { [weak gate] in
            gate?.dismiss(animated: true) {
                onSuccess()
            }
        }
        gate.modalPresentationStyle = .overFullScreen
        gate.modalTransitionStyle = .crossDissolve
        present(gate, animated: true)
    }
}

// MARK: - Scene navigation

/// Centralized scene transitions. Scenes call `SkyNavigator.shared.showX()`
/// rather than constructing SKTransition calls themselves — keeps routing
/// logic (paywall gating, music switching) in one place.
final class SkyNavigator {

    static let shared = SkyNavigator()

    private weak var view: SKView?
    private weak var presenter: GameViewController?

    private init() {}

    func attach(view: SKView, presenter: GameViewController) {
        self.view = view
        self.presenter = presenter
    }

    // MARK: - Entry points

    func showMenu() {
        present(MenuScene(size: sceneSize()), music: SkyMusic.menu)
    }

    func showMap() {
        present(MapScene(size: sceneSize()), music: SkyMusic.menu)
    }

    func showShop() {
        present(ShopScene(size: sceneSize()), music: SkyMusic.menu)
    }

    func showHangar() {
        present(HangarScene(size: sceneSize()), music: SkyMusic.menu)
    }

    func showUnlock() {
        present(UnlockScene(size: sceneSize()), music: SkyMusic.menu)
    }

    func showGame(challenge: Challenge) {
        let scene = GameScene(size: sceneSize(), challenge: challenge)
        present(scene, music: SkyMusic.gameplay)
    }

    func showResults(challenge: Challenge, coinsCollected: Int, hitsTaken: Int, didWin: Bool) {
        let scene = ResultsScene(
            size: sceneSize(),
            challenge: challenge,
            coinsCollected: coinsCollected,
            hitsTaken: hitsTaken,
            didWin: didWin
        )
        present(scene, music: didWin ? SkyMusic.menu : SkyMusic.menu)
    }

    func showFreeFlightCity() {
        present(FreeFlightCityScene(size: sceneSize()), music: SkyMusic.freeFlightCity)
    }

    func showFreeFlightMountain() {
        present(FreeFlightMountainScene(size: sceneSize()), music: SkyMusic.freeFlightMntn)
    }

    func presentParentalGate(onSuccess: @escaping () -> Void) {
        presenter?.presentParentalGate(onSuccess: onSuccess)
    }

    // MARK: - Internals

    private func sceneSize() -> CGSize {
        if let bounds = view?.bounds.size, bounds != .zero { return bounds }
        return UIScreen.main.bounds.size
    }

    private func present(_ scene: SKScene, music: String?) {
        guard let view = view else { return }
        scene.scaleMode = .resizeFill
        let transition = SKTransition.fade(withDuration: 0.35)
        view.presentScene(scene, transition: transition)

        if let music = music {
            AudioManager.shared.playMusic(music, fileExtension: "wav")
        }
    }
}
