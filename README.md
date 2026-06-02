# RepCounter

A watchOS app that automatically counts workout reps from wrist motion. Works for arm-driven exercises (curl, bench, row) and for lower-body lifts where the only signal reaching the wrist is body vibration (squat, leg press, deadlift).

- Set-based: tap **Start Workout**, lift, and sets auto-end after ~4 s of rest.
- Live on-screen rep count + per-rep haptic.
- HealthKit-backed workout session so the workout shows up in the Fitness app.
- No iPhone companion needed.

## How it works

Three layers:

1. **`MotionSampler`** — wraps `CMMotionManager` at 50 Hz in the `.xArbitraryZVertical` reference frame, so `accel.z` is the vertical component of user acceleration.
2. **`RepDetector`** — pure Swift signal-processing pipeline:
   - Band-pass IIR (0.25 Hz HPF + 4 Hz LPF) on the signed vertical-axis accel.
   - Rolling-RMS envelope over 2 s; threshold scales adaptively so a quiet leg-vibration registers at the same relative scale as a big arm swing.
   - Hysteresis peak detection produces one candidate per oscillation of the band-passed signal.
   - Rhythm confirmation: candidates are buffered and nothing is counted until 3 consecutive oscillations arrive at a consistent tempo. On lock-on the backlog is flushed at once (the count jumps straight to 3) and reps are then counted live. This rejects one-off / random motion and, by fixing the rep period before counting, sets the refractory (0.6× the observed period) so the secondary within-rep peak is rejected from the very first counted rep — no more counting both the start and the reversal of a rep.
   - Set-end fires when envelope drops below 30% of its peak and no rep has emitted for 4 s.
   - Absolute-spike + env-jump impact suppression for dropped weights.
3. **`WorkoutSession`** — orchestrates `HKWorkoutSession` + `MotionSampler` + `RepDetector`, exposes `@Observable` state to the SwiftUI view, and fires haptics on rep / set-end events.

The detector is pure logic with no Apple-framework dependencies, so it's fully unit-testable from synthetic signals.

## Build & run

Requirements: Xcode 26+, watchOS 10+ target, an Apple Watch Series 6+ (real device — many of the manual tests cannot run in the simulator).

```bash
git clone <this-repo>
cd repcounter
open RepCounter/RepCounter.xcodeproj
```

Before the first build you will need to:

1. Set your own **Team** and a unique **Bundle Identifier** under the `RepCounter Watch App` target → Signing & Capabilities. The committed values reference the original author's personal team and will not work for you.
2. Confirm the **HealthKit** capability is enabled on the same pane.
3. Confirm Info.plist has non-empty values for `NSMotionUsageDescription`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, and a `WKBackgroundModes` array containing `workout-processing`.

To run unit tests from the command line:

```bash
cd RepCounter
xcodebuild -project RepCounter.xcodeproj \
  -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)" \
  test
```

(Adjust the simulator name to one available on your machine via `xcrun simctl list devices`.)

## Project layout

```
RepCounter/
  RepCounter Watch App/
    RepCounterApp.swift          — @main entry
    Views/WorkoutView.swift      — idle / active / paused UI
    Session/WorkoutSession.swift — HK + observable state
    Motion/
      MotionSample.swift         — value type
      MotionSampler.swift        — CoreMotion wrapper
    Detection/
      BiquadFilter.swift         — IIR filter primitive
      DetectorEvent.swift        — .rep / .setEnded
      RepDetector.swift          — main algorithm
  RepCounterTests/
    BiquadFilterTests.swift
    RepDetectorTests.swift
    SignalGenerators.swift       — deterministic synthetic signals
    TraceReplayTests.swift       — replays JSON traces of real workouts
    traces/                      — drop recorded JSON traces here
```

## Recording real-world traces

The test suite can replay JSON traces of recorded workouts so you lock down detector behavior against ground truth. Each trace is:

```json
{
  "expected_reps": [10, 10, 10],
  "samples": [[t, ax, ay, az, gx, gy, gz], ...]
}
```

Drop files into `RepCounter/RepCounterTests/traces/` and `TraceReplayTests.testAllRecordedTraces` will pick them up automatically.

## License

MIT — see [LICENSE](LICENSE).
