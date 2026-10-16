# Value receipt — Flight Facts

| | |
|---|---|
| **Project** | Flight Facts (personal iPhone app) |
| **Hourly rate** | **$200/hr** |
| **Date started** | 2026-07-25 |
| **Format** | CLAUDE.md ledger + PROJECT-RULES.md fields, merged at CJ's choice (2026-10-16). Rows and detail blocks are append-only; only the totals row is updated. |

### How the numbers are made

- **Tokens:** measured. Read from this project's Claude Code session transcript
  (`~/.claude/projects/…/6d6e5abd….jsonl`), deduplicated per message and split at
  each of CJ's requests. Columns are input / output / cache write / cache read.
- **Cost:** **ESTIMATE**: API list-price equivalent (Opus 5: $5/$25/$10/$0.50
  per MTok; Opus 5.5: $4/$20/$8/$0.20, with 1-hour cache writes at 2× input). CJ
  is on the Max plan, so this is what the work *would* cost on the API, not a bill.
- **Elapsed:** measured. Active time from each request to the last reply in it.
- **Manual hours:** always **ESTIMATE**. What a skilled iOS developer would need
  without AI, with the basis given.
- **Plan usage:** the 5-hour window %, from the session usage tool. It wasn't
  captured before iteration 05.
- Each row covers usage up to when it was written. Any tail of that turn (the
  commit, the report) rolls into the next iteration's row.

## Ledger

| Iteration & date | Summary | Tokens (in / out / cache W / cache R) | Cost | Manual hours (ESTIMATE) | Elapsed | Hours saved · value | Plan 5h | Other value |
|---|---|---|---|---|---|---|---|---|
| **01** · 2026-07-25 | v1: sensor fusion, phase detector, offline POI corpus, bubble map UI, notifications, demo flights, RRCC replay, icon | 18,387,650 (173 / 164,856 / 241,926 / 17,980,695) | $15.53 ESTIMATE | 70 h. Basis: ~5,100 lines of Swift across 30 files at ~100 tested lines/hr, plus ~15 h researching and writing ~145 facts | 91 min | 68.5 h · **$13,697** | not recorded | 3 logic bugs caught in simulated flights; RRCC schema interop verified; app icon designed |
| **02** · 2026-07-25/26 | Toolchain fix guidance; code signing fixed for device install | 4,197,226 (28 / 9,508 / 262,161 / 3,925,529) | $4.82 ESTIMATE | 1.5 h. Basis: diagnosing an unsigned-build install failure and reconfiguring automatic signing | 8 min | 1.4 h · **$273** | not recorded | Signature verified end to end before handover |
| **03** · 2026-08-11 | Flight planner + seat side, map pre-warming, sky facts, compass, plane icon, keep-awake, +54 landmarks, +30 hangar talk | 20,723,838 (112 / 73,882 / 649,479 / 20,000,365) | $18.34 ESTIMATE | 24 h. Basis: ~1,200 new lines, 188-airport database, astronomy maths, ~85 researched facts | 182 min | 21.0 h · **$4,193** | not recorded | Root-caused slow maps (3D terrain); fixed repeating facts (12 repeats → 0) |
| **04** · 2026-10-16 | Real-flight fixes (climb read as taxi, frozen GPS), FPS, map spin, offline indicators, Lock Screen Live Activity, 15 tests, device install | 25,782,954 (94 / 122,783 / 556,677 / 25,103,400) | $11.93 ESTIMATE | 32 h. Basis: field-bug root cause from a report alone, ~1,500 new or rewritten lines, a widget extension, 15 scenario tests and a test harness | 23 min | 31.6 h · **$6,323** | not recorded | 12 bugs fixed (see block); 15 regression tests; AI model brought current |
| **05** · 2026-10-16 | Project setup: git, standards research, story, value receipt | 8,886,547 (28 / 28,205 / 624,222 / 8,234,092), measured to 17:55 UTC | $7.20 ESTIMATE | 4 h. Basis: standards review across Apple release notes, ActivityKit and Core Location docs, App Store requirements, plus repo and docs setup | 16 min | 3.7 h · **$747** | 18% | 1 functional bug found (Live Activity start); 6 deviations logged |
| **Running total** | 5 iterations | **77,978,215** (435 / 399,234 / 2,334,465 / 75,244,081) | **$57.82 ESTIMATE** | **131.5 h ESTIMATE** | **320 min** | **126.2 h · $25,233** | — | 24 errors fixed, 15 tests, 1 standards ledger |

---

## Iteration details

### Iteration 01 · 2026-07-25 · "A flight on paper"
- **Shipped:** SwiftUI app; GPS/barometer/IMU fusion; flight-phase detector with
  cold-start snap-in; offline landmark (115) and aviation-history corpus;
  chat-bubble feed over a heading-up map; local notifications; cabin advice;
  synthetic demo flights; RRCC TrackSession import/export; flight log; app icon.
- **Files:** ~33 added. **Lines of code:** ~5,085 Swift.
- **Builds/installs:** ~10 simulator builds; simulator installs only.
- **Errors fixed:** 2 compile errors; flight never saved on landing; 20 s
  cold-start delay; fast playback skipped takeoff; Info.plist overwritten by
  XcodeGen.

### Iteration 02 · 2026-07-25/26 · "Getting onto the phone"
- **Shipped:** automatic signing with team HUYKA6BQUX; README build notes.
- **Files:** 2 edited (`project.yml`, `README.md`).
- **Builds/installs:** 1 signed device build, verified with `codesign`.
- **Errors fixed:** unsigned device build (`0xe800801c`).

### Iteration 03 · 2026-08-11 · "Making it feel real"
- **Shipped:** flight planner with 188 airports and seat-side inference; route
  pre-warming via `MKMapSnapshotter`; seat-biased POI ranking; sky facts (solar
  elevation, horizon dip, moon phase); compass; corrected plane icon; keep-awake;
  chattiness setting; 169 landmarks; 60 hangar-talk items.
- **Files:** 7 added, ~10 edited. **Lines of code:** ~6,320 Swift.
- **Builds/installs:** ~12 simulator builds.
- **Errors fixed:** plane double rotation; compass overlapping controls; camera
  lagging the aircraft; repeating hangar talk; malformed Swift in sky facts.

### Iteration 04 · 2026-10-16 · "The first real flight"
- **Shipped:** `SensorFusion` (stale-fix detection, dead reckoning, per-field
  validity); detector rewritten as a state machine; barometric top-of-descent;
  airport gating for ground phases; smoothed display course and camera dead-band;
  blur-free UI and isolated map heading for frame rate; GPS/offline status pills;
  Lock Screen + Dynamic Island Live Activity; 15 unit tests; AI model updated.
- **Files:** 11 added, ~15 edited. **Lines of code:** 7,574 across 48 Swift files.
- **Builds/installs:** 2 signed device builds, 2 device installs, 3 macOS test-harness runs.
- **Errors fixed:** climb read as taxi; stale GPS replayed as live; unknown speed
  treated as zero; landing never detected at a higher destination; GPS running in
  the background while idle; car driving read as takeoff roll; barometer unused
  for descent; turbulence false alarm; POIs during taxi at high-elevation
  airports; prefetch warming the wrong tile set; AI `max_tokens` too small for
  thinking; odometer counting parked jitter.

### Iteration 05 · 2026-10-16 · "Putting the project on rails"
- **Shipped:** git repository; stack-appropriate `.gitignore`;
  `docs/STANDARDS.md` (sourced, dated); `docs/STORY.md` (prologue + 5 chapters);
  this ledger; `screenshots/`.
- **Files:** 4 added, 1 rewritten (`.gitignore`). No app code changed.
- **Builds/installs:** none. No app code changed, and the iPhone was disconnected.
- **Errors fixed:** 0. **Found:** Live Activity may be started from the background
  (Apple requires foreground), plus 5 lower-priority deviations.
- **Plan usage:** 5-hour window 18%; weekly (all models) 67%.
