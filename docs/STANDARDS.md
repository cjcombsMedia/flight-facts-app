# Standards — Flight Facts

Current official guidance for the stack, what this project actually uses, and
where the two differ. Recheck any entry older than 90 days, and whenever a new
framework is added.

**Last full check:** 2026-10-16 · **Next due:** 2027-01-14

## Toolchain and platform

| Item | Current standard | This project | Source | Checked |
|---|---|---|---|---|
| Xcode | Xcode 27 (27A266a). Includes Swift 6.4 and the iOS 27 SDK; requires macOS Tahoe 26.6+; debugs on iOS 17 and later. | Xcode 27.0 (27A266a) ✅ | [Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) | 2026-10-16 |
| Swift | Swift 6.4 ships in Xcode 27. | Toolchain 6.4 ✅ · **language mode Swift 5, strict concurrency `minimal`** ⚠️ | Xcode 27 Release Notes (above); local `swift --version` | 2026-10-16 |
| iOS SDK | iOS 27.0 SDK. | iOS 27.0 SDK ✅ · deployment target iOS 17.0 | [iOS & iPadOS 27 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) | 2026-10-16 |
| App Store build requirement | Since 2026-04-28, uploads must be built with Xcode 26+ against an iOS 26+ SDK. Since 2026-09-09, apps must target iOS 13 or later. | Xcode 27 / iOS 27 SDK, target iOS 17 ✅ | [Apple: SDK minimum requirements](https://developer.apple.com/news/upcoming-requirements/) | 2026-10-16 |
| Scene-based life cycle | "Apps built with the latest SDK must adopt the scene-based life cycle or they fail to launch." | SwiftUI `App` + `WindowGroup` (scene-based) ✅ — confirmed launching on device | iOS & iPadOS 27 Release Notes (UIKit) | 2026-10-16 |
| Launch screen | Apps built with the 27.0 SDK must declare `UILaunchScreen` (or a storyboard) in `Info.plist`. | `UILaunchScreen` present ✅ | iOS & iPadOS 27 Release Notes (UIKit) | 2026-10-16 |
| Project generation | XcodeGen 2.46.0 is the latest release. | 2.46.0 ✅ | [XcodeGen releases](https://github.com/yonaskolb/XcodeGen/releases) | 2026-10-16 |

## Frameworks

| Item | Current standard | This project | Source | Checked |
|---|---|---|---|---|
| ActivityKit (Live Activities) | Active for up to 8 h, then stays on the Lock Screen for up to 4 h more (12 h max). Static + dynamic data ≤ 4 KB combined. **"In general, your app needs to be in the foreground to start a Live Activity"** (background start only via a `LiveActivityIntent`). Updates and ends can happen from the background. `staleDate` flips `context.isStale`. Lock Screen presentation may be truncated above 160 pt. Requires `NSSupportsLiveActivities`. | Key present ✅ · state well under 4 KB ✅ · **starts the activity at flight detection, which can happen in the background** ❌ · `isStale` not rendered ⚠️ · flights over 8 h lose the banner ⚠️ | [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) | 2026-10-16 |
| Core Location | `CLLocationUpdate.liveUpdates(_:)` (async sequence, includes an `.airborne` configuration) with `CLBackgroundActivitySession` for background is the modern API since iOS 17. A new background session can only be started in the foreground. `CLLocationManager` remains supported. | `CLLocationManager` delegate with `activityType = .airborne` ⚠️ (supported, older pattern) | [CLLocationUpdate](https://developer.apple.com/documentation/corelocation/cllocationupdate), [WWDC23: Discover streamlined location updates](https://developer.apple.com/videos/play/wwdc2023/10180/), [Apple forums answer on CLBackgroundActivitySession](https://developer.apple.com/forums/thread/810433) | 2026-10-16 |
| Testing | Apple-ecosystem guidance is Swift Testing for new unit tests, XCTest for UI and performance tests; the two coexist in one target. Xcode 27 adds a cross-framework assertion interoperability setting. | XCTest unit tests ⚠️ | Xcode 27 Release Notes (Testing); [Swift Testing vs XCTest (third-party)](https://theswiftk.it.com/blog/swift-testing-vs-xctest-migration-guide-2026) | 2026-10-16 |
| MapKit for SwiftUI | `Map(position:)`, `MapCamera`, `MapStyle`, `MapPolyline`, `Annotation` (iOS 17+). | In use | **Not yet verified** against current docs — check next iteration | — |
| Anthropic Messages API | Swift has no official SDK, so raw HTTP is correct. Default model `claude-opus-5-5`; thinking is always on, `output_config.effort` is the only depth control; refusal fallbacks via `anthropic-beta: server-side-fallback-2026-07-01` + `"fallbacks": "default"`. | Matches ✅ | Claude API reference bundled with Claude Code (model table cached 2026-10-06) — not an official web page | 2026-10-16 |

## Deviations to resolve

Ranked by impact.

1. **Live Activity started from the background.** If the phone is locked when the
   flight is detected, the Lock Screen banner won't start. Fix: start it when
   the user taps *Start flight detect* (foreground), in a "scanning" state, then
   update it as the flight progresses.
2. **Live Activity ignores `isStale`.** Show a "stale" treatment when the app
   stops updating it.
3. **Flights longer than 8 hours.** The system ends the activity at 8 h. Consider
   ending and restarting it while the app is foregrounded, or accept the limit.
4. **Swift 5 language mode.** Move to Swift 6 language mode with complete
   concurrency checking once the sensor code is stable.
5. **XCTest instead of Swift Testing** for the unit tests. Low risk; migrate
   opportunistically.
6. **`CLLocationManager` delegate** rather than `CLLocationUpdate.liveUpdates`.
   Works; migrate if background behaviour proves unreliable in flight.

## Where sources disagreed

- swift.org's install pages listed **Swift 6.3.2** as the newest stable release,
  while Apple's Xcode 27 release notes say Xcode 27 **includes Swift 6.4**, and the
  local toolchain reports 6.4. This file records 6.4, the version actually in use.
- Several Live Activity facts circulate on third-party sites (update budgets,
  push cadence). Only the figures quoted from Apple's ActivityKit page above are
  treated as standards.
