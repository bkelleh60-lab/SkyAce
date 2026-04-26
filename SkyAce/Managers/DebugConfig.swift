//
//  DebugConfig.swift
//  SkyAce
//
//  Debug-only flag that bypasses the IAP paywall during testing so QA can
//  reach locked content without making real purchases.
//
//  Toggle: change `debugUnlockAllContent` below to `true` (bypass active) or
//  `false` (treat the IAP as not purchased even in dev). The flag, the
//  on-screen banner, and every bypass call site are wrapped in `#if DEBUG`,
//  so the Release configuration used for App Store builds compiles all of
//  this away — there is zero runtime cost and no symbols in the shipped
//  binary.
//
//  Real StoreKit code in `IAPManager` is intentionally NOT modified by this
//  flag; the bypass only affects the synchronous read accessors UI/scene
//  code uses to gate access to locked content.
//

import Foundation

#if DEBUG
/// When `true`, paywall checks return "unlocked" so testers can reach
/// premium content without purchasing. Stripped from Release builds.
let debugUnlockAllContent = true
#endif
