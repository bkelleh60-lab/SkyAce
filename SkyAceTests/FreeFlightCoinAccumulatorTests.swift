import XCTest
@testable import SkyAce

final class FreeFlightCoinAccumulatorTests: XCTestCase {

    // The contract: rate is 0.5. Test code asserts against the literal value
    // so a deliberate rate change has to update both the constant and the
    // tests, preventing accidental drift.
    func testRateConstantIsHalf() {
        XCTAssertEqual(FreeFlight.coinCreditRate, 0.5, accuracy: 1e-9)
    }

    func testSingleCoinDoesNotCreditButTwoCoinsCreditOne() {
        var acc = FreeFlight.CoinAccumulator()
        XCTAssertEqual(acc.credit(faceValue: 1), 0,
                       "One coin × 0.5 must round down to 0 — the half-coin stays as residual.")
        XCTAssertEqual(acc.credit(faceValue: 1), 1,
                       "Second coin lifts the residual to 1.0, so it credits.")
    }

    func testCoinStreamAveragesToHalfRate() {
        var acc = FreeFlight.CoinAccumulator()
        var total = 0
        for _ in 0..<100 {
            total += acc.credit(faceValue: 1)
        }
        XCTAssertEqual(total, 50,
                       "100 face-value-1 pickups must credit exactly 50 at a 0.5 rate.")
    }

    func testRingCreditsTwoWithHalfCoinResidual() {
        var acc = FreeFlight.CoinAccumulator()
        XCTAssertEqual(acc.credit(faceValue: 5), 2,
                       "5 × 0.5 = 2.5 → credit 2 now, hold 0.5 in residual.")
        XCTAssertEqual(acc.credit(faceValue: 1), 1,
                       "0.5 residual + 0.5 from this coin = 1.0 → credit 1.")
    }

    func testTwoRingsCreditFiveExactly() {
        var acc = FreeFlight.CoinAccumulator()
        let first = acc.credit(faceValue: 5)
        let second = acc.credit(faceValue: 5)
        XCTAssertEqual(first + second, 5,
                       "Two rings face-value-5 = 10 × 0.5 = 5 with no residual.")
    }

    func testMixedStreamHonoursRate() {
        var acc = FreeFlight.CoinAccumulator()
        // 3 rings + 6 coins = 21 face value × 0.5 = 10.5 → credit 10, leave 0.5.
        var total = 0
        total += acc.credit(faceValue: 5)
        total += acc.credit(faceValue: 1)
        total += acc.credit(faceValue: 1)
        total += acc.credit(faceValue: 5)
        total += acc.credit(faceValue: 1)
        total += acc.credit(faceValue: 1)
        total += acc.credit(faceValue: 5)
        total += acc.credit(faceValue: 1)
        total += acc.credit(faceValue: 1)
        XCTAssertEqual(total, 10)
    }

    func testZeroFaceValueIsNoOp() {
        var acc = FreeFlight.CoinAccumulator()
        XCTAssertEqual(acc.credit(faceValue: 0), 0)
        XCTAssertEqual(acc.credit(faceValue: 1), 0,
                       "Zero-value pickup must not erase the half-coin residual that follows.")
        XCTAssertEqual(acc.credit(faceValue: 1), 1)
    }
}
