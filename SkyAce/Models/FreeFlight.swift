import Foundation

/// Free Flight economy constants and helpers.
///
/// Free Flight (City + Mountain) is a no-fail sandbox. Pickups still credit
/// the player's persistent coin balance (`ProgressManager.shared.coins`) —
/// the same store the Shop and Hangar spend from — so blocked mission players
/// have a calm path to keep earning. The reduced credit rate below keeps
/// mission play as the efficient way to earn.
enum FreeFlight {

    /// Multiplier applied to Free Flight pickup face values when crediting
    /// the player's persistent coin balance. Mission play credits at 1.0;
    /// Free Flight credits at this rate. See SKY-67.
    static let coinCreditRate: Double = 0.5

    /// Converts a stream of integer-valued Free Flight pickups into an
    /// integer credit on the persistent coin balance.
    ///
    /// Coins have a face value of 1, so a per-pickup multiplication by 0.5
    /// would round down to 0 every time and quietly drop every coin. The
    /// accumulator carries the sub-coin residual across pickups so the
    /// average credit converges to `coinCreditRate × face value`.
    struct CoinAccumulator {

        private var residual: Double = 0

        /// Adds the rate-adjusted credit for one pickup to the running
        /// residual and returns the whole-coin portion that should be passed
        /// to `ProgressManager.shared.addCoins(_:)`. The fractional remainder
        /// stays in the accumulator for the next pickup.
        mutating func credit(faceValue: Int) -> Int {
            residual += Double(faceValue) * FreeFlight.coinCreditRate
            let credit = Int(residual.rounded(.down))
            residual -= Double(credit)
            return credit
        }
    }
}
