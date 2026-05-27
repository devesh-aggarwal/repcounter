# RepCounter — Apple Watch Auto Rep Counter (v1 Design)

**Date:** 2026-05-26
**Status:** Approved for implementation planning
**Target:** watchOS 10+, Apple Watch Series 6 and later

## Goal

A standalone watchOS app that detects and counts workout reps automatically by analyzing wrist motion. Works for arm-driven exercises (curl, bench, row) and for lower-body exercises where the user's body vibration is the only signal reaching the wrist (squat, leg press, deadlift).

## Non-goals (v1)

- No iPhone companion app
- No persisted workout history across launches
- No exercise classification or naming
- No social, sharing, or export features
- No iCloud sync

## User experience

### Flow

1. User opens the app. Sees an **Idle** screen with a "Start Workout" button.
2. User taps **Start Workout** → app requests Motion + HealthKit permissions on first launch, then enters **Active** state.
3. User begins exercising. The watch detects rhythmic motion and:
   - Increments a large on-screen rep counter
   - Delivers a `.click` haptic per rep
4. When the user stops moving rhythmically for ~4 seconds, the current set auto-ends:
   - Final count animates into a "Last set: N" chip
   - A `.success` haptic fires once
   - Counter resets to 0
5. User starts the next set; the cycle repeats automatically.
6. When done, user taps **End** → HKWorkoutSession is saved (so the workout shows in Activity rings + Fitness app).

### Screen states

| State   | Layout |
|---------|--------|
| Idle    | "Start Workout" button, centered |
| Active  | Set number (small, top) · rep count (large, center, monospaced digits) · "Last set: N" chip (below center, hidden until set 1 ends) · Pause / End buttons (bottom) |
| Paused  | Same as Active but counter dimmed, "Pause" → "Resume" |

A subtle pulse animation plays on the counter on each detected rep, in addition to the haptic.

### Permissions

- `NSMotionUsageDescription` (CoreMotion)
- HealthKit share for `HKWorkoutType` (read scope: none)

If denied, show a message + "Open Settings" deep link.

## Architecture

Three layers in a single watchOS SwiftUI target:

```
┌──────────────────────────┐
│  WorkoutView (SwiftUI)   │
└────────────┬─────────────┘
             │ observes
┌────────────▼─────────────┐
│  WorkoutSession          │   owns HKWorkoutSession,
│  (@Observable)           │   drives UI state,
│                          │   triggers haptics
└────────┬───────┬─────────┘
         │       │
         │       │ subscribes to RepEvent / SetEnded
         │       │
         │ ┌─────▼────────────┐
         │ │  RepDetector     │   band-pass + adaptive peak
         │ │                  │   detection algorithm
         │ └─────▲────────────┘
         │       │ consumes samples
         │       │
┌────────▼───────┴─────────┐
│  MotionSampler           │   CMMotionManager @ 50 Hz
│                          │   emits (t, accel, gyro)
└──────────────────────────┘
```

State flows one way: `MotionSampler` → `RepDetector` → `WorkoutSession` → `WorkoutView`. The view never touches motion APIs directly.

## Detection algorithm (Option A — adaptive peak detection)

### Sampling

- `CMMotionManager.startDeviceMotionUpdates` at 50 Hz (deviceMotionUpdateInterval = 0.02 s).
- Reference frame: `.xArbitraryZVertical` (gravity vector known, so we can use `userAcceleration` directly without computing it ourselves).

### Signal construction

Per sample, compute a single **signed** scalar by projecting `userAcceleration` onto the vertical (gravity) direction:

```
s(t) = userAcceleration(t) · ĝ(t)
```

where `ĝ(t)` is the gravity unit vector reported by CoreMotion. In the watch's local frame, gravity points along the wrist-frame's "down" direction; projecting onto it gives the component of motion that fights gravity. This is signed (positive when accelerating upward, negative when downward) so the band-pass filter and peak detector see a true one-peak-per-cycle signal.

**Why not vector magnitude?** Magnitude (`‖userAcceleration‖`) is always ≥ 0 — it rectifies a sinusoidal motion signal and doubles the apparent frequency. The detector would then count two reps per actual cycle. Projecting onto gravity preserves sign.

**Why drop gyro for v1?** Gyro magnitude rectifies the same way, and projecting gyro onto gravity gives only the rotation around the vertical axis (which is secondary for most strength exercises). v1 detects on accel projection alone. v2 can layer in gyro via a separate signed feature.

**Frame convention.** Incoming `MotionSample`s are assumed to be in a frame where the z-axis is roughly vertical. In production, `MotionSampler` will arrange this by using `.xArbitraryZVertical` reference frame. In tests, signal generators write motion on `accel.z` and the gravity unit is `(0, 0, 1)`.

### Band-pass filter

Two cascaded biquad IIR filters applied to `s(t)`:

- High-pass at **0.25 Hz** — removes gravity drift and slow posture changes
- Low-pass at **4 Hz** — removes hand tremor, impact spikes, and rapid jitter

The passband (0.3–3 Hz) covers slow heavy lifts (≈3 sec/rep) through fast movements (≈0.33 sec/rep).

### Adaptive envelope

Maintain a rolling RMS of the filtered signal over a 2-second window — call this `env`.

Peak threshold:

```
θ = max(noise_floor, k · env)
k = 0.5
noise_floor = 0.02 g
```

The hard `noise_floor` prevents phantom reps from a still wrist. The adaptive component (`k · env`) is what lets a quiet leg-day vibration register at the same relative scale as a big arm swing.

### Peak detection

A rep is emitted when:

1. The filtered signal crosses `+θ` going up, then
2. Reaches a local maximum, then
3. Crosses back below `0.5 · θ` (hysteresis), AND
4. At least `T_refractory` has elapsed since the last rep.

`T_refractory` starts at 333 ms (corresponds to the 3 Hz cap). After 3 confirmed reps, estimate the actual cadence and set:

```
T_refractory = 0.6 · observed_period
```

This avoids double-counting a rep with a small secondary bump while still allowing legitimate fast reps.

### Set-end detection

Fire `SetEnded` when both:

- `env` has fallen below 30% of its peak observed during this set, AND
- No new rep has been emitted for **4 seconds**

The current rep count is moved to "last set"; the current count resets to 0; detection continues seamlessly into the next set.

### Edge cases

- **Warmup:** The first 500 ms of a session feeds the filters but emits no reps (avoids filter transient artifacts).
- **Impact suppression:** If `env` jumps 5× over a 200 ms window, suppress rep emission for 300 ms (handles dropping the bar, dumbbell clinks).
- **Pause:** Motion sampling stops; HK session stays alive; on resume, treat the next 500 ms as warmup again.

## Background execution

`HKWorkoutSession` with:

- `activityType = .traditionalStrengthTraining`
- `locationType = .indoor`

This is required so motion sampling continues when the wrist drops or the screen turns off — and it gives the user credit for the workout in Activity rings.

The HKLiveWorkoutBuilder is started/stopped alongside the session. We do not collect heart rate or energy samples in v1 (HK manages those defaults for the workout type).

## Components & responsibilities

### `MotionSampler`

- **Purpose:** Wrap CoreMotion and emit a clean stream of motion samples in a gravity-aligned frame.
- **Interface:**
  - `start()` / `stop()`
  - Emits `MotionSample = (timestamp: TimeInterval, accel: SIMD3<Double>, gyro: SIMD3<Double>)` where `accel` is `userAcceleration` and `gyro` is `rotationRate`, both expressed in CoreMotion's `.xArbitraryZVertical` reference frame so the z-axis is roughly vertical. The detector uses `accel.z` as its signed primary signal.
- **Depends on:** `CMMotionManager`

### `RepDetector`

- **Purpose:** Convert motion samples into rep / set-end events.
- **Interface:**
  - `process(_ sample: MotionSample)`
  - `events: AsyncStream<DetectorEvent>` where `DetectorEvent = .rep | .setEnded(count: Int)`
  - `reset()`
- **Internals:** Biquad high-pass + low-pass, rolling RMS envelope, peak state machine, refractory timer.
- **Depends on:** Nothing (pure logic — fully unit-testable).

### `WorkoutSession`

- **Purpose:** Orchestrate the workout lifecycle and expose observable state for the UI.
- **Interface (`@Observable`):**
  - State: `phase: .idle | .active | .paused`, `currentSetReps: Int`, `lastSetReps: Int?`, `setNumber: Int`
  - Actions: `start()`, `pause()`, `resume()`, `end()`
- **Internals:** Owns the `HKWorkoutSession`, `HKLiveWorkoutBuilder`, `MotionSampler`, and `RepDetector`. Subscribes to detector events; updates state; triggers `WKInterfaceDevice.current().play(.click)` per rep and `.success` on set end.
- **Depends on:** `HealthKit`, `MotionSampler`, `RepDetector`, `WatchKit` (for haptics).

### `WorkoutView`

- **Purpose:** Render the three UI states and dispatch user actions to the session.
- **Depends on:** `WorkoutSession`.

## Testing

### Unit tests (XCTest) on `RepDetector`

All tests feed synthetic sample streams; none require a device.

| Scenario | Input | Expected |
|---|---|---|
| Clean periodic signal | Pure sine, amp 0.5 g, at 0.5 / 1 / 2 / 3 Hz, 10 cycles each | reps == 10 ± 1 |
| Rising amplitude | Sine 1 Hz, amp ramps 0.1 g → 1.0 g over 10 cycles | reps == 10 ± 1 |
| Subtle vibration (leg-day case) | Sine 0.7 Hz, amp 0.05 g, on top of σ=0.02 g Gaussian noise | reps detected; count == cycles ± 1 |
| Still-wrist sensor noise | σ=0.01 g Gaussian noise, 10 s | reps == 0 |
| Single impact spike | Flat + one 3 g pulse | reps == 0 |
| Set-end timing | Sine 1 Hz for 5 s, then flat | `setEnded` fires within 4.0 ± 0.5 s of motion stopping |
| Refractory | Sine 1 Hz with secondary bump 100 ms after each peak | reps == 1 per cycle (not 2) |

### Recorded-trace tests

A debug build flag enables recording raw motion to a file during real workouts. Check 3+ traces into `tests/traces/`:

- `bench-3x10.json`
- `back-squat-3x5.json`
- `leg-press-watch-on-wrist.json` (the "vibration only" case)

Each trace is annotated with the ground-truth rep count per set. The test harness replays each trace through `RepDetector` and asserts the count matches within ±1 per set.

### On-device manual checklist (pre-release)

- [ ] Bench press 3×10 — counts within ±1
- [ ] Back squat 3×5 — counts within ±1 (vibration-only)
- [ ] Bicep curl 3×12 — counts within ±1
- [ ] Walking around / no workout — produces no false reps
- [ ] Workout appears in Fitness app afterward
- [ ] Haptic timing feels synchronous with reps
- [ ] App stays running with wrist down / screen off

### Out of scope for v1 tests

- UI snapshot tests
- HealthKit save integration tests (manual verification only)

## Open questions / known risks

- **Refractory tuning** — the 0.6× factor is a starting guess; recorded-trace tests will tell us if it needs adjustment.
- **Noise floor calibration** — 0.02 g is a starting point; may need per-device tuning if older Apple Watches have noisier IMUs.
- **High-noise environment rejection** — v1 unit tests verify rejection of still-wrist sensor noise (σ ≈ 0.01 g). Rejection of high-amplitude ambient motion (walking around with no exercise, σ ≈ 0.05 g) is verified manually on-device (Task 14's "walking around" check). If false-positives occur during manual testing, v2 should add a periodicity gate that requires consistent inter-peak intervals before emitting reps.
- **HealthKit authorization** — HKWorkoutSession is required for background motion sampling, so the app cannot function without it. If the user denies HealthKit, show a blocking message with an "Open Settings" deep link rather than attempting a degraded foreground-only mode.
