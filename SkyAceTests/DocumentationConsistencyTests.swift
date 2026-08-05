import XCTest

/// Regression tests for [SKY-109](https://linear.app/skyace/issue/SKY-109).
///
/// `DebugConfig.swift` and its `debugUnlockAllContent` flag were deleted from
/// the codebase as part of the SKY-107 IAP/StoreKit removal, but several
/// top-level docs kept referencing the deleted type. SKY-109 scrubbed those
/// stale references from `CLAUDE.md`, `README.md`, and
/// `docs/app-store-screenshots/CAPTURE.md`. These tests read the docs
/// straight off disk and assert the removed references stay gone, so a
/// future edit can't silently reintroduce them.
final class DocumentationConsistencyTests: XCTestCase {

    // MARK: - File loading

    /// `SkyAceTests/DocumentationConsistencyTests.swift` lives one directory
    /// below the repo root, so walking up from this source file's own path
    /// gives a build-machine-independent way to locate the docs under test.
    private static var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SkyAceTests/
            .deletingLastPathComponent() // repo root
    }

    private func contents(of relativePath: String) throws -> String {
        let url = Self.repoRootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let docPaths = [
        "CLAUDE.md",
        "README.md",
        "docs/app-store-screenshots/CAPTURE.md",
    ]

    // MARK: - CLAUDE.md

    func testClaudeMdDoesNotReferenceDebugConfig() throws {
        let text = try contents(of: "CLAUDE.md")
        XCTAssertFalse(text.contains("DebugConfig"),
                        "CLAUDE.md must not reference the deleted DebugConfig manager.")
        XCTAssertFalse(text.contains("debugUnlockAllContent"),
                        "CLAUDE.md must not reference the deleted debugUnlockAllContent flag.")
    }

    func testClaudeMdManagersNoteListsExactlyTheSurvivingManagers() throws {
        let text = try contents(of: "CLAUDE.md")
        XCTAssertTrue(
            text.contains("Cross-cutting state lives in `SkyAce/Managers/` (`ProgressManager`,"),
            "Managers architecture note should still introduce ProgressManager."
        )
        XCTAssertTrue(
            text.contains("`IAPManager`, `AudioManager`). Plain data types live in"),
            "Managers architecture note should list IAPManager and AudioManager, with the trailing DebugConfig entry removed."
        )
    }

    // MARK: - README.md

    func testReadmeDoesNotReferenceDebugConfig() throws {
        let text = try contents(of: "README.md")
        XCTAssertFalse(text.contains("DebugConfig"),
                        "README.md must not reference the deleted DebugConfig manager.")
        XCTAssertFalse(text.contains("debugUnlockAllContent"),
                        "README.md must not reference the deleted debugUnlockAllContent flag.")
    }

    func testReadmeProjectLayoutManagersLineOmitsDebugConfig() throws {
        let text = try contents(of: "README.md")
        XCTAssertTrue(
            text.contains("Managers/          ProgressManager, AudioManager, IAPManager"),
            "Project layout tree should list the three surviving managers with no trailing DebugConfig entry."
        )
    }

    // MARK: - docs/app-store-screenshots/CAPTURE.md

    func testCaptureMdDoesNotReferenceDebugConfig() throws {
        let text = try contents(of: "docs/app-store-screenshots/CAPTURE.md")
        XCTAssertFalse(text.contains("DebugConfig"),
                        "CAPTURE.md must not reference the deleted DebugConfig manager.")
        XCTAssertFalse(text.contains("debugUnlockAllContent"),
                        "CAPTURE.md must not reference the deleted debugUnlockAllContent flag.")
    }

    func testCaptureMdPreCaptureChecklistOmitsDebugConfigItem() throws {
        let text = try contents(of: "docs/app-store-screenshots/CAPTURE.md")
        XCTAssertFalse(
            text.contains("is `false` in the build being captured"),
            "The removed pre-capture checklist item asserting DebugConfig.debugUnlockAllContent == false must not reappear."
        )
    }

    func testCaptureMdSlotSixInstructionsRequireRealStoreKitPurchase() throws {
        let text = try contents(of: "docs/app-store-screenshots/CAPTURE.md")
        XCTAssertTrue(
            text.contains("Complete a StoreKit test purchase via the `SkyAce.storekit` config."),
            "Slot 6 instructions should require an actual StoreKit test purchase."
        )
        XCTAssertFalse(
            text.contains("Either complete a StoreKit test purchase"),
            "The old 'either StoreKit purchase or debug flag' phrasing should have been replaced with a single required path."
        )
        XCTAssertFalse(
            text.contains("temporarily flip"),
            "Slot 6 instructions must not offer the removed debugUnlockAllContent shortcut."
        )
    }

    func testCaptureMdDoneChecklistOmitsDebugConfigItem() throws {
        let text = try contents(of: "docs/app-store-screenshots/CAPTURE.md")
        XCTAssertFalse(
            text.contains("is `false` in committed code"),
            "The removed done-check item asserting debugUnlockAllContent == false must not reappear."
        )
    }

    /// Negative/boundary check: the PR only removed the DebugConfig-specific
    /// checklist item, not the separate, still-valid reminder about the
    /// generic "temporary debug flag" workflow. This guards against an
    /// overly broad future cleanup accidentally deleting unrelated content.
    func testCaptureMdRetainsUnrelatedTemporaryDebugFlagChecklistItem() throws {
        let text = try contents(of: "docs/app-store-screenshots/CAPTURE.md")
        XCTAssertTrue(
            text.contains("Premium content unlocked via either StoreKit test purchase (preferred) or temporary debug flag (must be reverted before commit)."),
            "The unrelated pre-capture checklist item about the generic temporary debug flag workflow must remain untouched."
        )
    }

    // MARK: - Cross-file regression

    func testNoTrackedDocReferencesDebugConfigAnywhere() throws {
        for path in Self.docPaths {
            let text = try contents(of: path)
            XCTAssertFalse(text.contains("DebugConfig"), "\(path) still references DebugConfig.")
            XCTAssertFalse(text.contains("debugUnlockAllContent"), "\(path) still references debugUnlockAllContent.")
        }
    }
}