# GymTrack

A beautifully simple gym tracker for **iPhone + Apple Watch** — now with
**automatic rep counting**. Slide to set the weight on every lift, watch your
progress build, and let the watch *count your reps for you* from wrist motion.

> GymTrack and the standalone **RepCounter** project have been merged into this
> one app. GymTrack contributes the full iPhone/Watch tracking experience;
> RepCounter contributes its motion-based rep-detection engine, which now powers
> automatic rep counting inside the GymTrack watch app. There is one app, one
> data store, and one Xcode project.

## Highlights

### Automatic rep counting (the merged-in superpower)

On the watch, open an exercise, dial in the weight with the Digital Crown, then
tap **Count Reps**. GymTrack reads your wrist motion at 50 Hz and counts each
rep with a tap on the wrist — no buttons. When you rack the weight and rest, the
set is **logged automatically** (a completed set at your chosen weight) and the
counter re-arms for the next set. Works for arm-driven lifts (curl, bench, row)
and for lower-body lifts where the only signal at the wrist is body vibration
(squat, leg press, deadlift). Manual **Log** is always there as a fallback.

The detector is a pure-Swift signal-processing pipeline (band-pass IIR →
rolling-RMS envelopes → movement-episode detection → rhythm confirmation →
impact suppression), unit-tested from synthetic signals and recorded traces. It
runs under a `WKExtendedRuntimeSession` so counting survives the screen
sleeping mid-set.

### iPhone app

- **Track tab** — one slider card per exercise. Drag the gradient slider or tap
  +/- to set your working weight; every change logs with haptic feedback,
  collapsed to one data point per day.
- **Last-time memory & PR detection** — each card shows what you lifted last
  session, and celebrates new all-time bests.
- **Plate calculator** — exact plates to load per side, with a barbell visual.
- **Rest timer** — per-exercise countdown that floats above the tab bar,
  survives backgrounding, and fires a local notification when rest is up.
- **Set counter** — track completed *of* target sets; the device pulses once per
  completed set on both iPhone and Apple Watch.
- **Progress tab** — Swift Charts line graph per exercise plus derived stats
  (total change, weekly rate, personal best, session count) and an activity
  heatmap.
- **Coaching insights** — trending up / deload nudge / plateau alerts.
- **AI Coach** *(optional)* — bring your own OpenAI key for a streaming chat
  coach built from your exercise history.
- **CSV export**, **custom exercises**, **weekly Push/Pull/Legs schedule**,
  **HealthKit workout sync**, and an optional **gym geofence** reminder.
- **Persistent, private storage** — everything is stored on-device with
  **SwiftData** (CloudKit-synced when enabled).

### Apple Watch app

- Today's split as a vertical list; tap an exercise to focus.
- **Digital Crown** weight picker with per-detent haptics.
- **Automatic rep counting + auto-logged sets** (above).
- Full-screen, wall-clock-accurate **rest timer**.
- Shares the **same SwiftData store** as the phone (CloudKit), so a set logged
  on the wrist shows up on the phone and vice-versa.

## How rep counting fits in

```
MotionSampler (CoreMotion, 50 Hz, .xArbitraryZVertical)
        │  MotionSample(accel, gyro)
        ▼
RepDetector (band-pass → envelopes → episode + rhythm detection)
        │  DetectorEvent .rep / .setEnded(count:)
        ▼
AutoRepSession (@Observable, WKExtendedRuntimeSession lifecycle)
        │  onRep → per-rep haptic   onSetEnded → log the set
        ▼
WatchExerciseView → exercise.logSet() + ProgressEntry(weight) in SwiftData
```

The engine lives in `GymTrackWatch Watch App/RepEngine/` and has no
Apple-framework dependencies beyond CoreMotion in `MotionSampler`, so the
detector is fully unit-testable.

## Requirements

- Xcode 16+ (project format `objectVersion = 77`; built on Xcode 26).
- iOS 17.0+ (SwiftData, Swift Charts) and watchOS 26+.
- Automatic rep counting needs a real Apple Watch (Series 6+); CoreMotion reps
  cannot be exercised in the simulator.

## Build & run

1. Open `GymTrack.xcodeproj`.
2. Select the **GymTrack** scheme + an iOS 17 simulator/device, and the
   **GymTrackWatch Watch App** scheme for the watch.
3. Set your own **Team** and unique **Bundle Identifiers** under each target's
   Signing & Capabilities (the committed values reference the original author's
   team and will not work for you).
4. The watch target already declares `NSMotionUsageDescription` and a
   `physical-therapy` entry in `WKBackgroundModes` (see
   `GymTrackWatch-Watch-App-Info.plist`) so it may sample motion in the
   background while you lift.

### Unit tests (rep-detection engine)

```bash
xcodebuild -project GymTrack.xcodeproj \
  -scheme "GymTrackWatch Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" \
  test
```

(Adjust the simulator name via `xcrun simctl list devices`.) Drop recorded
workout traces as JSON into `GymTrackWatchTests/traces/` and `TraceReplayTests`
will replay them against ground-truth rep counts.

## Project layout

```
GymTrack.xcodeproj
GymTrack/                        iPhone app (SwiftData models, views, theme)
GymTrackWatch Watch App/         watchOS app
  GymTrackWatchApp.swift           @main + shared SwiftData schema
  WatchTodayView.swift             today's split list
  WatchExerciseView.swift          weight picker + automatic rep counting
  WatchRestTimerView.swift         rest countdown
  WatchHaptics.swift / WatchSeedData.swift
  RepEngine/                       merged-in RepCounter engine
    BiquadFilter.swift             IIR filter primitive
    MotionSample.swift             value type
    MotionSampler.swift            CoreMotion wrapper
    DetectorEvent.swift            .rep / .setEnded
    RepDetector.swift              the detection algorithm
    AutoRepSession.swift           glue: engine <-> SwiftData + runtime session
GymTrackWatchTests/              detector unit tests + synthetic signals + traces
GymTrackWatch-Watch-App-Info.plist
```

See `AppStoreMetadata.md` for App Store submission notes.

## License

MIT — see [LICENSE](LICENSE).
