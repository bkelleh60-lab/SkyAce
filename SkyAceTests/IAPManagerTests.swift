import XCTest
@testable import SkyAce

@MainActor
final class IAPManagerTests: XCTestCase {

    func testIsContentUnlocked_returnsTrueInDebugBuilds() {
        // The DEBUG bypass flag is documented to short-circuit the paywall
        // accessor for QA. Tests run in DEBUG, so this must hold.
        #if DEBUG
        XCTAssertTrue(debugUnlockAllContent,
                      "Tests assume the DEBUG bypass flag is on.")
        XCTAssertTrue(IAPManager.shared.isContentUnlocked)
        #endif
    }

    func testEntitlementDidChangeNotificationName() {
        XCTAssertEqual(IAPManager.entitlementDidChange.rawValue, "IAPEntitlementDidChange")
    }

    func testEntitlementDidChangeNotificationFiredOnTransition() {
        let manager = IAPManager.shared

        // Force a known starting state, then flip and assert the
        // transition notification fires exactly once on the change.
        manager.setFullyUnlockedForTesting(false)

        let exp = expectation(forNotification: IAPManager.entitlementDidChange,
                              object: manager,
                              handler: nil)
        exp.expectedFulfillmentCount = 1

        manager.setFullyUnlockedForTesting(true)
        // A repeat of the same value must NOT post a second notification.
        manager.setFullyUnlockedForTesting(true)

        wait(for: [exp], timeout: 1.0)

        // Restore for other tests / app state.
        manager.setFullyUnlockedForTesting(false)
    }

    func testEntitlementDidChangeNotFiredWhenValueUnchanged() {
        let manager = IAPManager.shared
        manager.setFullyUnlockedForTesting(false)

        let exp = expectation(forNotification: IAPManager.entitlementDidChange,
                              object: manager,
                              handler: nil)
        exp.isInverted = true

        manager.setFullyUnlockedForTesting(false)

        wait(for: [exp], timeout: 0.5)
    }
}
