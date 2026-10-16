# Flight Facts — the story

## Prologue

Flight Facts is CJ's personal iPhone app for the window seat. It answers one
question: *what am I flying over?* From a passenger's seat you see canyons,
volcanoes, cities and coastlines go by with no idea what they are. The seatback
map doesn't know, and at 38,000 feet there's usually no internet to ask.

The app turns the phone's own sensors into the answer. GPS gives position,
speed and track. The barometer reads cabin pressure, which tracks climb and
descent even when GPS can't. The motion sensors feel turbulence. A bundled
library of landmarks and aviation history works with no connection at all. The
result reads like a chat, with bubbles floating over a moving map: what's out
the left window, why it looks that way, and what happened here in aviation
history. Cabin-crew style nudges come too: tray table up, you're starting down.

It's built for one user, CJ, on CJ's own iPhone, so the bar is "delightful on
my next flight," not App Store review. Its recordings share a format with CJ's
RRCC tracking app, so a session from one opens in the other. It's also a test
of how far a Claude-built app can get when every iteration is checked against a
real flight.

---

## Chapter 1 — A flight on paper

*Iteration 01 · 2026-07-25*

The goal was a first version, built to see whether the idea held up at all. We
built it in SwiftUI with MapKit, Core Location and Core Motion, and modelled
every sensor reading on the schema of CJ's RRCC app so the two would
interoperate. Because nobody was on a plane, the key design decision was a
single sensor pipeline: real sensors, a synthetic gate-to-gate demo flight, and
a replay of CJ's own RRCC recording all fed the same detector, fact engine and
notifications. Running full demo flights caught three real bugs: a flight never
saved because "landed" required a complete stop, opening the app at cruise
still waited 20 seconds before reacting, and fast playback skipped the takeoff
roll entirely. All three were fixed before handover. The landmark and aviation
corpus was bundled rather than fetched, on the reasoning that an app about
what's below you is useless if it needs Wi-Fi. By the end, CJ's real RRCC file
replayed straight into the app and snapped to cruise at 40,494 ft.

*Screenshot:* none archived. Simulator captures from this iteration weren't kept.

## Chapter 2 — Getting onto the phone

*Iteration 02 · 2026-07-25 to 26*

The goal was to run the app on CJ's iPhone instead of the simulator. The Mac's
command-line tools pointed at the wrong Xcode, which CJ fixed with one
`xcode-select` command. Then the first device install failed with "No code
signature found." The cause was a shortcut from iteration 01: signing had been
switched off so simulator builds needed no team, and that silently produced an
unsigned binary the phone refused. Automatic signing with CJ's team fixed it,
and the signature was verified before handover. The lesson: a setting that
makes one target easy can quietly break another.

*Screenshot:* none. No UI changed.

## Chapter 3 — Making it feel real

*Iteration 03 · 2026-08-11*

CJ's first hands-on feedback: maps loaded slowly, the plane icon pointed the
wrong way, there was no compass, the screen went dark, and there weren't enough
facts. The slow maps traced mainly to 3D terrain, which downloads an elevation
mesh that's invisible from cruise altitude, so it now defaults off. The icon was
rotated twice, once by the heading-up map and again by the icon itself. We
added flight planning (188 bundled airports, seat side inferred from "12A") so
facts favour the window you're actually at, and map pre-warming along the route
while you still have gate Wi-Fi. Pre-warming came with an honest caveat: MapKit
has no offline mode. Sun and moon facts computed from astronomy, with no data
files needed, joined 54 more landmarks and 30 more hangar-talk pieces. Testing
turned up a quieter problem: the facts pool looped, so 62% of the feed became
aviation facts with 12 repeats. It now goes quiet instead of repeating itself.

*Screenshot:* none archived.

## Chapter 4 — The first real flight

*Iteration 04 · 2026-10-16*

This was the turning point. CJ took the app on an actual flight, and at about
2,200 feet it froze, then announced that the aircraft was taxiing. Two bugs had
compounded. The detector only believed the aircraft was airborne above 195
knots, while airliners climb out at 150 to 180. And when GPS dropped out in the
cabin, the app kept replaying the last fix as if it were live. The fixes went
in together: a sensor-fusion layer that spots stale fixes and dead-reckons, and
a detector that can only return to the ground on low ground speed. Altitude
can't be the test, because CJ's PHX→MEX route lands 1,900 m higher than it
leaves. The same pass removed what made the map spin at the gate (GPS heading
noise) and what made it stutter (blur effects re-rendered every frame). It also
added a Lock Screen Live Activity and 15 regression tests reproducing the
in-flight failure. With no simulator available on the updated toolchain, the
tests ran as a small Mac program, and that caught one more real bug: parked GPS
jitter was adding to the distance travelled. The lesson: real flights find what
simulated ones can't, so each real-world failure now becomes a test.

*Screenshot:* none. Installed straight to the iPhone 16 Pro for CJ to test.

## Chapter 5 — Putting the project on rails

*Iteration 05 · 2026-10-16*

The goal was to adopt CJ's project rules: a git repository, a standards
ledger, this story and a value receipt. The standards check went to Apple's own
documentation rather than memory. It confirmed the app already met iOS 27's two
new launch requirements (the scene-based life cycle and a declared launch
screen). It also turned up something more useful: Apple's ActivityKit guide
says an app generally must be in the foreground to start a Live Activity. Flight
Facts starts its Lock Screen banner when it detects the flight, which can happen
with the phone already locked, so that's now the top item to fix. Two of CJ's
rule files disagreed on how to keep the value receipt, and CJ chose to merge
them into one ledger at $200 an hour. Because the app is for CJ alone, App Store
rules were recorded but don't drive decisions.

*Screenshot:* none. The iPhone was disconnected during this iteration.
