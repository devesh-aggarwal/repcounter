## What this is

**GymTrack** — a gym tracker for iPhone + Apple Watch, in a single Xcode project
(`GymTrack.xcodeproj`). It is the merge of two former apps:

- **GymTrack** (the iPhone/Watch tracking app): SwiftData store, Track/Progress/
  AI/Settings tabs, plate calculator, rest timer, weekly split schedule,
  HealthKit sync, CSV export, geofence.
- **RepCounter** (a motion rep-counting engine): now folded into the watch app
  under `GymTrackWatch Watch App/RepEngine/`. It auto-counts reps from wrist
  motion for arm-driven lifts (curl, bench, row) and lower-body lifts where the
  only wrist signal is body vibration (squat, leg press, deadlift).

## Targets

- `GymTrack` — iOS app (SwiftData models in `GymTrack/Models`, views in
  `GymTrack/Views`). iOS 17+.
- `GymTrackWatch Watch App` — watchOS 26+ app. The watch re-declares the shared
  SwiftData models (`Exercise`, `ProgressEntry`, `SplitDay`) inline in
  `GymTrackWatchApp.swift` so the target compiles standalone; they mirror the
  iOS schema byte-for-byte for a shared CloudKit store.
- `GymTrackWatchTests` — unit tests for the rep-detection engine (hosted on the
  watch app). Module name for `@testable import` is `GymTrackWatch_Watch_App`.

## Automatic rep counting

In `WatchExerciseView`: pick the weight with the Digital Crown, tap **Count
Reps**, and `AutoRepSession` runs `MotionSampler` + `RepDetector`. Each rep
fires a haptic; on a detected set-end (rest after a run of reps) the set is
auto-logged into SwiftData (`exercise.logSet()` + a `ProgressEntry` at the
chosen weight) and the counter re-arms for the next set. Manual **Log** remains
as a fallback. Counting survives the screen sleeping via
`WKExtendedRuntimeSession` (`physical-therapy` background mode +
`NSMotionUsageDescription`, declared via `GymTrackWatch-Watch-App-Info.plist`
and watch build settings).

The detector (`RepEngine/`) is pure logic with no Apple-framework dependency
except CoreMotion in `MotionSampler`, so it is fully unit-testable.

## Notes

- The data schema is intentionally unchanged by the merge (no `reps` field on
  `ProgressEntry`) so existing CloudKit-synced stores keep working; a detected
  set logs as one completed set at the chosen weight.
- The build cannot be compiled in this Linux environment — changes touching the
  Xcode project or Swift sources should be verified with `xcodebuild` on macOS.
