# Flight Facts

An iOS app that tells you what you're flying over, as you fly over it. Chat
bubbles float on a moving map: landmarks, geology, oddities, aviation history,
and cabin advice timed to what the aircraft is actually doing.

Built as a first iteration — complete and runnable, designed to keep iterating on.

---

## Running it

Built with Xcode 27 (iOS 27 SDK); deployment target is iOS 17. Three targets:
the app, `FlightFactsLiveActivity` (Lock Screen / Dynamic Island), and
`FlightFactsTests`.

The `.xcodeproj` is generated, not checked in. Regenerate it any time:

```bash
xcodegen generate
```

Build and install straight onto a cabled iPhone (find its id with
`xcrun devicectl list devices`):

```bash
xcodebuild -project FlightFacts.xcodeproj -scheme FlightFacts -configuration Debug -destination 'id=<DEVICE_ID>' -allowProvisioningUpdates -derivedDataPath build/DerivedData build
```

```bash
xcrun devicectl device install app --device <DEVICE_ID> "build/DerivedData/Build/Products/Debug-iphoneos/Flight Facts.app"
```

Signing is automatic and `DEVELOPMENT_TEAM` is pinned to `HUYKA6BQUX` in
`project.yml`. If anyone else builds this, change that value (or clear it and
pick a team in Xcode's Signing & Capabilities) — otherwise device builds fail
with `No code signature found`.

### Driving a demo without touching the UI

```bash
xcrun simctl launch booted com.cjcombs.flightfacts -autodemo lax-jfk -demoSpeed 240
```

`-autodemo` takes a route id (`lax-jfk`, `sea-mia`, `mex-lax`) or the name of a
bundled recording (`rrcc-sample`). Handy for iterating on the in-flight UI
without waiting at a simulated gate.

---

## What's in it

**Flight detection that works whenever you start it.** A state machine over
`atGate → taxi → takeoffRoll → climb → cruise → descent → approach → landed`.
Three things make it hold up:

- *Cold-start snap-in.* Open the app already at 38,000 ft doing 480 knots and it
  commits to `cruise` immediately, with no debounce — the point of catching a
  flight in progress is defeated if you have to watch a scanner first.
- *Debounce everywhere else.* A candidate phase has to hold for N seconds before
  it sticks, so one bad GPS fix or a turbulence bump can't flip the state.
- *Corroboration.* Speed and altitude come from GPS. Vertical rate is a 12-second
  least-squares fit, not GPS vertical velocity (which is noise). Cabin pressure
  and airframe vibration are independent sensors. Confidence is their weighted
  agreement, and the scanner screen shows you the reasoning as it happens.

**Every sensor that earns its place.** GPS, barometer (`CMAltimeter`), IMU
(`CMDeviceMotion` at 20 Hz for turbulence energy and turn rate), battery. The
barometer is the quiet hero: in a pressurised cabin it reads *cabin* altitude,
which tracks the pressurisation schedule, so it gives an independent vote on
climb vs. descent even when GPS is confused.

**Points of interest with geometry.** POIs are ranked by a `wow` score, their own
`reach` (the Grand Canyon is worth mentioning from much further out than a
museum), the geometric horizon at your current altitude, and whether the thing is
actually still ahead of you. Each call-out tells you *which window* and *what
clock position*.

**Plan a route before you fly.** Enter origin, destination and seat (`PHX` →
`MEX`, left window) and you get three things:

- *Map preloading.* Renders the corridor through `MKMapSnapshotter` on the ground,
  which pulls those tiles into MapKit's cache. See the caveat below.
- *Seat bias.* POI ranking favours your side of the aircraft. It's a nudge, not a
  filter — something big on the far side still gets called, but it's labelled
  "other side of the aircraft" so you know to lean.
- *A preview* of what the route will pass, with each item marked to a window.

188 airports are bundled; the route is a great circle, not a filed flight plan.

**A compass and a correctly-pointed aircraft.** The map is heading-up, so the
aircraft glyph is drawn relative to the *camera* heading rather than true north —
otherwise it double-rotates. The compass holds true north and taps to reset the
map to north-up.

**Screen stays awake in flight.** Held on while a flight is active so you can
glance at the map without unlocking. It's a real battery cost over five hours;
there's a toggle in Settings.

**Aviation history and sky facts.** Date-matched "on this day" entries,
location-matched history (Kitty Hawk, Edwards, Gander, Roswell, Mojave), 60 pieces
of hangar talk, and sun/moon facts computed from closed-form astronomy — including
the good one, that at 38,000 ft your horizon is depressed ~3.4° so the sun sets
about twenty minutes later than for anyone below you.

Chattiness is a setting (relaxed / standard / chatty) controlling POI sweep
interval, how many POIs may be called at once, and filler pacing. The hangar-talk
pool deliberately does **not** wrap — once exhausted it goes quiet rather than
repeating itself.

**Cabin advice tied to real transitions.** The valuable one is top of descent:
picked up from the barometer roughly 25 minutes and 100 miles before landing,
well before the PA announcement. Tray tables, seat backs, belts, plus stretch and
hydration nudges on the hour.

**It works in airplane mode.** The landmark and aviation-history corpus is
bundled. An app about what's below you that needs Wi-Fi to say anything would be
useless in the one place you'd want it.

**Notifications.** Local only — no server, works at altitude. Descent, takeoff and
border crossings go out as time-sensitive; everything else respects the settings
toggles and a rate floor so a 240× demo doesn't machine-gun you.

**Flight log.** Every flight saves two artefacts: a `FlightLog` (route, POIs, full
transcript, stats) and a `TrackSession-*.json` in **your RRCC schema-3 wire
format**, so sessions move between the two apps.

---

## Architecture

```
FlightFacts/
├── App/          FlightFactsApp, RootView, Theme, AppSettings
├── Models/       FlightSample (RRCC-compatible), FlightPhase, POI, Bubble, Geo
├── Sensors/      LocationService, MotionService, LiveSensorSource
├── Flight/       FlightDetector, FlightEngine, FlightRecorder, ReplaySource
├── Facts/        LandmarkStore, AviationHistory, MilestoneWatcher, POIScout,
│                 ClaudeFactService
├── Cabin/        CabinAdvisor
├── Notifications/NotificationService
├── Views/        Preflight, Scanner, Flight, FlightMap, BubbleFeed, Log,
│                 Arrival, Settings
└── Resources/    landmarks.json, aviation_history.json, rrcc-sample.json
```

The key structural decision: **everything downstream of the sensors only ever
sees `FlightSample`**. A real aircraft, a synthetic demo route and a replayed
RRCC file are three implementations of one `SampleSource` protocol, so the demo
exercises the exact same detector, POI scout, advisor and notification path a
real flight does. Nothing is faked below the sensor layer.

`FlightEngine` is the single `@Observable` the UI talks to. Content cadence is
measured in *sample* time, not wall time, so pacing scales correctly under replay.

### Data model

`FlightSample` mirrors your RRCC `TrackSession` schema 3 key-for-key — `spd`,
`course`, `alt`, `asc`/`dsc`, `baro`, `pressure`, `hAcc`/`vAcc`, `gyro`, `rms`,
`peak`, `odo`, `tank`, `hr`, `rrMs`. A recording from either app decodes in the
other. Fields your watch provides and a phone can't (`hr`, `rrMs`) are optional.

---

## Phase detection, after the first real flight

The first real flight broke at 2,200 ft and called the climb "taxiing". Two
bugs compounded:

1. **Airborne was only recognised above ~195 kt.** Below that the detector fell
   through to ground logic: accelerating → takeoff roll, otherwise → taxi. An
   airliner climbs out at 150–180 kt. Now airborne means flying speed (>87 kt)
   plus height above the runway or a real climb/sink rate — and once airborne,
   the *only* way back to the ground is ground speed below ~58 kt. Altitude can't
   be the landing test: PHX → MEX lands 1,900 m higher than it took off.
2. **A dead GPS fix was replayed as live.** Cabins attenuate GPS, and airplane
   mode drops assisted-GPS. CoreLocation keeps handing back the last fix, and the
   sampler re-stamped it as current — which froze every reading. `SensorFusion`
   now notices the fix going stale after 6 s, dead-reckons along the last course,
   and flags the sample `est`. Estimated samples never drive a phase change,
   with one deliberate exception: a sustained fall in *cabin* pressure-altitude at
   cruise is the top of descent, so that alert still fires with no satellites.

Also: speed `-1` (unknown) was being clamped to 0 (stopped); course is now only
trusted above ~8 kt, which is what stopped the map spinning at the gate; and
ground phases only start a flight near an airport, so scanning in the car on the
way there no longer "detects" a takeoff roll on the highway.

## Lock Screen

A Live Activity shows the phase, altitude, the latest fact and route progress on
the Lock Screen and in the Dynamic Island. Updates are pushed locally by the app
(alive all flight thanks to background location), so it needs no server and
works in airplane mode. Updates are coalesced to one per four seconds — iOS
rate-limits redraws — except cabin-crew alerts, which go immediately. If the app
dies, the banner greys out after 15 minutes rather than showing stale data.

## Tests

`FlightFactsTests` covers the detector and GPS fusion with flight profiles fed
one sample per second, including the exact failure from the first flight
(climb-out below 195 kt, then GPS loss at 2,200 ft), landing at a higher
destination, barometric top-of-descent with GPS out, cold start mid-climb, and
false positives (gate jitter, highway driving). Run them in Xcode with ⌘U on a
device. `LockScreenRenderTests` renders the Lock Screen layout to a PNG.

## Verified earlier, in the simulator

- Full MEX→LAX demo gate-to-gate: 6 POIs, 58 feed entries, 804 track points,
  correct phase progression through descent → approach → landed → arrival summary.
- Both artefacts written to disk; the exported `TrackSession` validates against
  schema 3 with exactly the RRCC key set.
- Your actual `TrackSession-2026-07-25-102014.json` replayed: decodes straight
  through and snap-ins to cruise at 40,494 ft / 549 mph / Mach 0.83.

## On slow maps

Three separate things were making the map slow, in descending order of impact:

1. **3D terrain.** `elevation: .realistic` downloads an elevation mesh on top of
   the imagery. At cruise the camera is 260 km up and the relief is invisible
   anyway, so this was pure cost. Now defaults off, with a toggle.
2. **No preloading.** Hence the route prefetch above.
3. **Camera animation stacking.** The follow camera animated over a fixed 0.9 s,
   which is fine at 1 Hz but queues up under fast replay and leaves the aircraft
   drifting off-centre. Now scaled to the real gap between samples.

And, separately, frame rate:

- **Blur over a moving map.** Every panel and bubble used `.ultraThinMaterial`,
  which re-blurs whatever is behind it every frame. With a dozen of them over a
  constantly moving map that dominated the GPU. They're solid translucent fills.
- **The whole map rebuilt every frame.** The camera heading lived in `@State` on
  the map view and MapKit reports it per frame, so every frame rebuilt the map's
  content, polylines included. It now lives in its own observable read only by
  the compass and the aircraft marker.
- **Unbounded track.** One polyline point per second, capped at 4,000. Now spaced
  by distance and thinned past 1,500.

The honest limit on preloading: MapKit has no public prefetch API and no supported
offline mode. `MKMapSnapshotter` renders through the same tile pipeline, so the
tiles land in MapKit's shared cache — but that cache is the system's, with no
documented size or eviction policy. This makes the map much faster. It does not
make it work with the radio off.

---

## Notes and caveats

**The Claude API key.** Optional AI-generated facts fill gaps over places nobody
hand-wrote an entry for. The key is stored in the Keychain and called directly
from the device, which is fine for a personal build. If this ever ships to other
people, move the call behind a server you control — a key embedded in a
distributed app is a key you've given away.

**Facts are hand-written and checked, but not sourced.** ~110 landmarks and ~30
aviation history entries. If this grows, the entries should carry a source field.

**Background location** requires the `location` background mode (declared) and
either Always authorization or the blue status bar. Set up but not exercised on
device.

---

## Where I'd go next

1. **Pre-flight corridor prefetch.** Given a route, cache POIs and any online
   enrichment along the whole corridor while you still have gate Wi-Fi. This is
   the single biggest quality win — it makes online enrichment useful in the air
   instead of only on the ground.
2. **Flight number lookup.** Type your flight number at the gate, get the real
   route, actual aircraft type, and tail-number history ("this exact airframe has
   been flying since 2009").
3. **Replay your real flights as test fixtures.** Every flight already exports a
   `TrackSession`; dropping those into the detector tests would catch the next
   real-world surprise the way the 2,200 ft one should have been caught.
4. **A wider corpus, and let it grow.** 169 landmarks covers the obvious. Ocean
   crossings and much of Asia and Africa are thin.
5. **Watch app.** Wrist taps for POIs are less intrusive than a phone, and it
   would pick up the `hr`/`rrMs` fields the schema already carries.
