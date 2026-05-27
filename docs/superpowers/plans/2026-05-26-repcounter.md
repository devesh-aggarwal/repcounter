# RepCounter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a watchOS app that automatically detects and counts workout reps from wrist motion, including subtle vibrations from lower-body exercises.

**Architecture:** Three layers — `MotionSampler` (CoreMotion @ 50 Hz) → `RepDetector` (band-pass IIR + adaptive peak detection) → `WorkoutSession` (HKWorkoutSession + observable UI state) → `WorkoutView` (SwiftUI). Detection logic is pure Swift and fully unit-testable from synthetic signals and recorded traces.

**Tech Stack:** Swift 5.9, SwiftUI, watchOS 10+, CoreMotion, HealthKit, WatchKit (haptics), XCTest. Xcode 15+.

**Spec:** See `docs/superpowers/specs/2026-05-26-repcounter-design.md`.

---

## File Structure

```
RepCounter.xcodeproj/                          # Xcode project (created in Task 1)
RepCounter Watch App/
  RepCounterApp.swift                           # @main entry point
  Info.plist                                    # NSMotionUsageDescription, HK keys
  Views/
    WorkoutView.swift                           # Idle / Active / Paused UI
  Session/
    WorkoutSession.swift                        # @Observable orchestrator
  Motion/
    MotionSample.swift                          # struct MotionSample
    MotionSampler.swift                         # CMMotionManager wrapper
  Detection/
    BiquadFilter.swift                          # IIR biquad (pure logic)
    RepDetector.swift                           # Main detector
    DetectorEvent.swift                         # enum DetectorEvent
RepCounterTests/
  BiquadFilterTests.swift
  RepDetectorTests.swift
  SignalGenerators.swift                        # sine, noise, impulse helpers
  TraceReplayTests.swift                        # replay JSON traces
  traces/
    .gitkeep                                    # real traces added during manual testing
```

Boundary rules:
- `BiquadFilter` and `RepDetector` import nothing from CoreMotion / HealthKit / UIKit. They take/return plain values and are unit-testable on macOS via `xcodebuild test`.
- `MotionSampler` is the only file that touches `CMMotionManager`.
- `WorkoutSession` is the only file that touches `HealthKit` and `WatchKit`.

---

## Task 1: Create Xcode project scaffolding

**Files:**
- Create: `RepCounter.xcodeproj/` (via Xcode UI)
- Create: `RepCounter Watch App/RepCounterApp.swift`
- Create: `RepCounter Watch App/Views/WorkoutView.swift` (placeholder)

This task is mostly Xcode UI work. The agent walks the user through it because Xcode projects can't be created cleanly from CLI.

- [ ] **Step 1: Create the Xcode project**

In Xcode 15+:
1. File → New → Project
2. Choose **watchOS → App**, click Next
3. Product Name: `RepCounter`
4. Interface: **SwiftUI**, Language: **Swift**
5. Check **Include Tests**
6. Save into `/Users/devesh/code/repcounter/` (Xcode will create `RepCounter.xcodeproj` here)

- [ ] **Step 2: Set deployment target to watchOS 10**

Select the `RepCounter Watch App` target → General → Minimum Deployments → watchOS 10.0.

- [ ] **Step 3: Replace the default app entry**

Open `RepCounter Watch App/RepCounterApp.swift` and replace with:

```swift
import SwiftUI

@main
struct RepCounterApp: App {
    var body: some Scene {
        WindowGroup {
            WorkoutView()
        }
    }
}
```

- [ ] **Step 4: Create placeholder WorkoutView**

Create folder `Views/` under `RepCounter Watch App/`. Create `Views/WorkoutView.swift`:

```swift
import SwiftUI

struct WorkoutView: View {
    var body: some View {
        Text("RepCounter")
    }
}

#Preview {
    WorkoutView()
}
```

- [ ] **Step 5: Verify build**

Run from `/Users/devesh/code/repcounter/`:
```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build
```
Expected: `BUILD SUCCEEDED`.

(If that simulator name doesn't exist, run `xcrun simctl list devices | grep "Apple Watch"` and substitute a name that does.)

- [ ] **Step 6: Initial commit**

```bash
git add .
git commit -m "feat: scaffold watchOS app with placeholder view"
```

---

## Task 2: BiquadFilter — IIR filter primitive

**Files:**
- Create: `RepCounter Watch App/Detection/BiquadFilter.swift`
- Create: `RepCounterTests/BiquadFilterTests.swift`

Pure-Swift Direct Form II Transposed biquad. We use two instances per pipeline: one high-pass, one low-pass.

- [ ] **Step 1: Write the failing tests**

Create `RepCounterTests/BiquadFilterTests.swift`:

```swift
import XCTest
@testable import RepCounter_Watch_App

final class BiquadFilterTests: XCTestCase {

    func testLowPassAttenuatesHighFrequency() {
        // 50 Hz sample rate, low-pass cutoff at 4 Hz.
        let lpf = BiquadFilter.lowPass(sampleRate: 50, cutoff: 4)
        // Drive with 20 Hz sine for 2 s (well above cutoff).
        var maxAmp = 0.0
        for i in 0..<100 {
            let t = Double(i) / 50.0
            let x = sin(2 * .pi * 20 * t)
            let y = lpf.process(x)
            if i > 25 { maxAmp = max(maxAmp, abs(y)) } // skip transient
        }
        XCTAssertLessThan(maxAmp, 0.2, "20 Hz should be heavily attenuated by 4 Hz LPF")
    }

    func testLowPassPassesLowFrequency() {
        let lpf = BiquadFilter.lowPass(sampleRate: 50, cutoff: 4)
        // Drive with 1 Hz sine — well below cutoff.
        var maxAmp = 0.0
        for i in 0..<250 {
            let t = Double(i) / 50.0
            let x = sin(2 * .pi * 1 * t)
            let y = lpf.process(x)
            if i > 50 { maxAmp = max(maxAmp, abs(y)) }
        }
        XCTAssertGreaterThan(maxAmp, 0.8, "1 Hz should pass nearly unchanged through 4 Hz LPF")
    }

    func testHighPassAttenuatesDC() {
        let hpf = BiquadFilter.highPass(sampleRate: 50, cutoff: 0.25)
        // Drive with constant 1.0 (DC) for 10 s.
        var maxAmp = 0.0
        for i in 0..<500 {
            let y = hpf.process(1.0)
            if i > 250 { maxAmp = max(maxAmp, abs(y)) }
        }
        XCTAssertLessThan(maxAmp, 0.01, "DC should be removed by HPF")
    }

    func testHighPassPassesMidBand() {
        let hpf = BiquadFilter.highPass(sampleRate: 50, cutoff: 0.25)
        var maxAmp = 0.0
        for i in 0..<500 {
            let t = Double(i) / 50.0
            let x = sin(2 * .pi * 1 * t)
            let y = hpf.process(x)
            if i > 250 { maxAmp = max(maxAmp, abs(y)) }
        }
        XCTAssertGreaterThan(maxAmp, 0.8, "1 Hz should pass nearly unchanged through 0.25 Hz HPF")
    }
}
```

Add this file to the `RepCounterTests` target in Xcode (drag into target, check the test target).

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | grep -E "(error:|FAIL|PASS)"
```

Expected: build errors — `BiquadFilter` does not exist.

- [ ] **Step 3: Implement BiquadFilter**

Create folder `Detection/` under `RepCounter Watch App/`. Create `Detection/BiquadFilter.swift`:

```swift
import Foundation

/// Direct-Form II Transposed biquad IIR filter.
/// Coefficients derived using RBJ Audio EQ Cookbook formulas (Q = 1/sqrt(2)).
final class BiquadFilter {
    private let b0, b1, b2, a1, a2: Double
    private var z1: Double = 0
    private var z2: Double = 0

    private init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    func reset() { z1 = 0; z2 = 0 }

    static func lowPass(sampleRate: Double, cutoff: Double) -> BiquadFilter {
        let q = 1.0 / sqrt(2.0)
        let w0 = 2.0 * .pi * cutoff / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        let b0 = (1.0 - cosw0) / 2.0 / a0
        let b1 = (1.0 - cosw0) / a0
        let b2 = (1.0 - cosw0) / 2.0 / a0
        let a1 = -2.0 * cosw0 / a0
        let a2 = (1.0 - alpha) / a0
        return BiquadFilter(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    static func highPass(sampleRate: Double, cutoff: Double) -> BiquadFilter {
        let q = 1.0 / sqrt(2.0)
        let w0 = 2.0 * .pi * cutoff / sampleRate
        let cosw0 = cos(w0)
        let alpha = sin(w0) / (2.0 * q)
        let a0 = 1.0 + alpha
        let b0 = (1.0 + cosw0) / 2.0 / a0
        let b1 = -(1.0 + cosw0) / a0
        let b2 = (1.0 + cosw0) / 2.0 / a0
        let a1 = -2.0 * cosw0 / a0
        let a2 = (1.0 - alpha) / a0
        return BiquadFilter(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }
}
```

Add the file to the `RepCounter Watch App` target.

- [ ] **Step 4: Run tests and verify they pass**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | tail -20
```

Expected: all 4 BiquadFilter tests pass.

- [ ] **Step 5: Commit**

```bash
git add "RepCounter Watch App/Detection/BiquadFilter.swift" RepCounterTests/BiquadFilterTests.swift RepCounter.xcodeproj
git commit -m "feat: add biquad IIR filter primitive"
```

---

## Task 3: MotionSample and DetectorEvent types

**Files:**
- Create: `RepCounter Watch App/Motion/MotionSample.swift`
- Create: `RepCounter Watch App/Detection/DetectorEvent.swift`

Plain value types shared across layers. No tests — they're data carriers.

- [ ] **Step 1: Create MotionSample**

Create folder `Motion/`. Create `Motion/MotionSample.swift`:

```swift
import Foundation
import simd

/// A single 50 Hz motion measurement.
/// - timestamp: seconds since some monotonic reference (e.g. `Date().timeIntervalSince1970`).
/// - accel: linear acceleration (g), gravity removed.
/// - gyro: rotation rate (rad/s).
struct MotionSample {
    let timestamp: TimeInterval
    let accel: SIMD3<Double>
    let gyro: SIMD3<Double>
}
```

Add to `RepCounter Watch App` target.

- [ ] **Step 2: Create DetectorEvent**

Create `Detection/DetectorEvent.swift`:

```swift
import Foundation

enum DetectorEvent: Equatable {
    case rep
    case setEnded(count: Int)
}
```

Add to `RepCounter Watch App` target.

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add "RepCounter Watch App/Motion/MotionSample.swift" "RepCounter Watch App/Detection/DetectorEvent.swift" RepCounter.xcodeproj
git commit -m "feat: add MotionSample and DetectorEvent value types"
```

---

## Task 4: Signal generator test helpers

**Files:**
- Create: `RepCounterTests/SignalGenerators.swift`

Reusable test fixtures for synthetic signals. No production code yet.

- [ ] **Step 1: Create SignalGenerators**

```swift
import Foundation
import simd
@testable import RepCounter_Watch_App

enum SignalGenerators {

    static let sampleRate: Double = 50.0
    static var dt: Double { 1.0 / sampleRate }

    /// Sine wave on the X axis of acceleration, zero gyro.
    static func sine(frequency: Double, amplitude: Double, duration: Double,
                     startTime: TimeInterval = 0) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = startTime + Double(i) * dt
            let v = amplitude * sin(2 * .pi * frequency * t)
            return MotionSample(timestamp: t,
                                accel: SIMD3(v, 0, 0),
                                gyro: SIMD3(0, 0, 0))
        }
    }

    /// Sine with amplitude ramping linearly from a0 to a1 across the duration.
    static func sineRamp(frequency: Double, a0: Double, a1: Double, duration: Double) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = Double(i) * dt
            let frac = Double(i) / Double(max(n - 1, 1))
            let amp = a0 + (a1 - a0) * frac
            let v = amp * sin(2 * .pi * frequency * t)
            return MotionSample(timestamp: t, accel: SIMD3(v, 0, 0), gyro: SIMD3(0, 0, 0))
        }
    }

    /// Gaussian noise (Box-Muller). Deterministic via seed.
    static func noise(sigma: Double, duration: Double, seed: UInt64 = 42) -> [MotionSample] {
        var rng = SeededRNG(seed: seed)
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = Double(i) * dt
            let u1 = max(rng.nextDouble(), 1e-12)
            let u2 = rng.nextDouble()
            let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
            return MotionSample(timestamp: t, accel: SIMD3(sigma * z, 0, 0), gyro: SIMD3(0, 0, 0))
        }
    }

    /// Flat zero signal (used to terminate a set in tests).
    static func silence(duration: Double, startTime: TimeInterval = 0) -> [MotionSample] {
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            MotionSample(timestamp: startTime + Double(i) * dt,
                         accel: SIMD3(0, 0, 0), gyro: SIMD3(0, 0, 0))
        }
    }

    /// Add two sample streams element-wise (assumes equal length).
    static func add(_ a: [MotionSample], _ b: [MotionSample]) -> [MotionSample] {
        precondition(a.count == b.count)
        return zip(a, b).map { (sa, sb) in
            MotionSample(timestamp: sa.timestamp,
                         accel: sa.accel + sb.accel,
                         gyro: sa.gyro + sb.gyro)
        }
    }
}

/// Linear-congruential RNG so tests are deterministic.
struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed | 1 }
    mutating func nextDouble() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
```

Add to `RepCounterTests` target only.

- [ ] **Step 2: Verify build of tests**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  build-for-testing 2>&1 | tail -5
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add RepCounterTests/SignalGenerators.swift RepCounter.xcodeproj
git commit -m "test: add synthetic signal generators for detector tests"
```

---

## Task 5: RepDetector — clean periodic signal detection

**Files:**
- Create: `RepCounter Watch App/Detection/RepDetector.swift`
- Create: `RepCounterTests/RepDetectorTests.swift`

Implement the full detector in one go — it's a tightly-coupled state machine that's hard to land in pieces. The first tests exercise the happy path (clean periodic signal); subsequent tasks add tests for edge cases.

- [ ] **Step 1: Write the failing tests**

Create `RepCounterTests/RepDetectorTests.swift`:

```swift
import XCTest
@testable import RepCounter_Watch_App

final class RepDetectorTests: XCTestCase {

    private func runDetector(on samples: [MotionSample]) -> [DetectorEvent] {
        let detector = RepDetector(sampleRate: 50)
        var events: [DetectorEvent] = []
        detector.onEvent = { events.append($0) }
        for s in samples { detector.process(s) }
        return events
    }

    private func repCount(_ events: [DetectorEvent]) -> Int {
        events.filter { if case .rep = $0 { return true } else { return false } }.count
    }

    // 10 cycles of clean 1 Hz sine at amp 0.5 g → expect ~10 reps.
    func testCleanSine1Hz() {
        let samples = SignalGenerators.sine(frequency: 1.0, amplitude: 0.5, duration: 10.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testCleanSine05Hz() {
        let samples = SignalGenerators.sine(frequency: 0.5, amplitude: 0.5, duration: 20.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }

    func testCleanSine2Hz() {
        let samples = SignalGenerators.sine(frequency: 2.0, amplitude: 0.5, duration: 5.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | grep -E "(error:|FAIL)"
```

Expected: errors — `RepDetector` does not exist.

- [ ] **Step 3: Implement RepDetector**

Create `Detection/RepDetector.swift`:

```swift
import Foundation
import simd

/// Detects rhythmic reps in a motion sample stream.
/// Algorithm: combined accel+gyro magnitude → band-pass (0.25 Hz HPF + 4 Hz LPF)
/// → adaptive envelope (rolling RMS) → hysteresis peak detection with refractory.
final class RepDetector {

    // MARK: Tunables (see spec § Detection algorithm)
    private let sampleRate: Double
    private let gyroWeight: Double = 0.3
    private let envWindowSeconds: Double = 2.0
    private let thresholdK: Double = 0.5
    private let noiseFloor: Double = 0.02
    private let hysteresisFactor: Double = 0.5
    private let initialRefractory: Double = 0.333
    private let refractoryFactor: Double = 0.6
    private let setEndQuietSeconds: Double = 4.0
    private let setEndEnvDropFraction: Double = 0.3
    private let warmupSeconds: Double = 0.5
    private let impactRatio: Double = 5.0
    private let impactWindowSeconds: Double = 0.2
    private let impactSuppressSeconds: Double = 0.3

    // MARK: Filters
    private let hpf: BiquadFilter
    private let lpf: BiquadFilter

    // MARK: State
    private var startTime: TimeInterval?
    private var lastSampleTime: TimeInterval = 0
    private var envSumSq: Double = 0           // running sum of squares for RMS
    private var envBuffer: [Double] = []
    private var envBufferCapacity: Int
    private var peakEnvThisSet: Double = 0
    private var lastRepTime: TimeInterval? = nil
    private var refractory: Double
    private var inPeak: Bool = false
    private var peakMax: Double = 0
    private var currentSetReps: Int = 0
    private var lastImpactSuppressUntil: TimeInterval = 0
    private var envHistoryShort: [Double] = [] // for impact detection
    private var envShortCapacity: Int

    /// Callback fired for each detector event. Called synchronously inside `process`.
    var onEvent: ((DetectorEvent) -> Void)?

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.hpf = BiquadFilter.highPass(sampleRate: sampleRate, cutoff: 0.25)
        self.lpf = BiquadFilter.lowPass(sampleRate: sampleRate, cutoff: 4.0)
        self.envBufferCapacity = Int(envWindowSeconds * sampleRate)
        self.envShortCapacity = Int(impactWindowSeconds * sampleRate)
        self.refractory = initialRefractory
    }

    func reset() {
        hpf.reset(); lpf.reset()
        startTime = nil
        lastSampleTime = 0
        envSumSq = 0
        envBuffer.removeAll(keepingCapacity: true)
        envHistoryShort.removeAll(keepingCapacity: true)
        peakEnvThisSet = 0
        lastRepTime = nil
        refractory = initialRefractory
        inPeak = false
        peakMax = 0
        currentSetReps = 0
        lastImpactSuppressUntil = 0
    }

    func process(_ sample: MotionSample) {
        let t = sample.timestamp
        if startTime == nil { startTime = t }
        lastSampleTime = t
        let elapsed = t - (startTime ?? t)

        // 1. Combine acceleration and rotation into a single magnitude signal.
        let accelMag = length(sample.accel)
        let gyroMag = length(sample.gyro)
        let s = accelMag + gyroWeight * gyroMag

        // 2. Band-pass filter (HPF then LPF).
        let hp = hpf.process(s)
        let f = lpf.process(hp)

        // 3. Update rolling RMS envelope.
        envBuffer.append(f * f)
        envSumSq += f * f
        if envBuffer.count > envBufferCapacity {
            envSumSq -= envBuffer.removeFirst()
        }
        let env = sqrt(envSumSq / Double(envBuffer.count))

        // 4. Impact suppression: env jumping 5× over 200 ms window?
        envHistoryShort.append(env)
        if envHistoryShort.count > envShortCapacity {
            envHistoryShort.removeFirst()
        }
        if let oldEnv = envHistoryShort.first,
           oldEnv > 1e-6,
           env / oldEnv >= impactRatio {
            lastImpactSuppressUntil = t + impactSuppressSeconds
        }

        // 5. Warmup gate: feed filters but emit no reps in first 0.5 s.
        guard elapsed >= warmupSeconds else { return }

        // 6. Refractory + impact-suppression gates.
        let refractoryOK: Bool = {
            guard let last = lastRepTime else { return true }
            return (t - last) >= refractory
        }()
        let impactOK = t >= lastImpactSuppressUntil

        // 7. Peak detection state machine with hysteresis.
        let threshold = max(noiseFloor, thresholdK * env)
        if !inPeak {
            if f > threshold && refractoryOK && impactOK {
                inPeak = true
                peakMax = f
            }
        } else {
            peakMax = max(peakMax, f)
            if f < threshold * hysteresisFactor {
                // Emit rep at descent through hysteresis.
                inPeak = false
                emitRep(at: t, env: env)
            }
        }

        // 8. Set-end detection.
        peakEnvThisSet = max(peakEnvThisSet, env)
        if currentSetReps > 0 {
            let envDropped = env < peakEnvThisSet * setEndEnvDropFraction
            let quiet = (lastRepTime.map { (t - $0) >= setEndQuietSeconds } ?? false)
            if envDropped && quiet {
                onEvent?(.setEnded(count: currentSetReps))
                currentSetReps = 0
                peakEnvThisSet = 0
                refractory = initialRefractory
                lastRepTime = nil
            }
        }
    }

    private func emitRep(at t: TimeInterval, env: Double) {
        // Track period for adaptive refractory.
        if let last = lastRepTime {
            let period = t - last
            currentSetReps += 1
            // After 3 reps, lock refractory to 0.6 × observed period.
            if currentSetReps >= 3 {
                refractory = max(0.1, refractoryFactor * period)
            }
        } else {
            currentSetReps += 1
        }
        lastRepTime = t
        onEvent?(.rep)
    }
}
```

Add to `RepCounter Watch App` target.

- [ ] **Step 4: Run tests and verify they pass**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | tail -20
```

Expected: 3 RepDetector tests pass + previous BiquadFilter tests still pass.

- [ ] **Step 5: Commit**

```bash
git add "RepCounter Watch App/Detection/RepDetector.swift" RepCounterTests/RepDetectorTests.swift RepCounter.xcodeproj
git commit -m "feat: add RepDetector with adaptive peak detection"
```

---

## Task 6: RepDetector — noise rejection & subtle-vibration cases

**Files:**
- Modify: `RepCounterTests/RepDetectorTests.swift`

Adds tests for the spec's "leg-day vibration" case and pure-noise rejection. No production code changes expected — if these fail, tune constants.

- [ ] **Step 1: Add the failing/regression tests**

Append to `RepCounterTests/RepDetectorTests.swift` inside the test class:

```swift
    func testPureNoiseProducesNoReps() {
        let samples = SignalGenerators.noise(sigma: 0.05, duration: 10.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertEqual(reps, 0, "Pure noise should not produce any reps")
    }

    func testSubtleVibrationOnNoise() {
        // Spec: 0.7 Hz sine, amp 0.05 g, on top of σ=0.02 g noise. Expect rep ≈ cycles.
        let sine = SignalGenerators.sine(frequency: 0.7, amplitude: 0.05, duration: 14.0) // 14 s × 0.7 = ~10 cycles
        let noise = SignalGenerators.noise(sigma: 0.02, duration: 14.0)
        let mixed = SignalGenerators.add(sine, noise)
        let reps = repCount(runDetector(on: mixed))
        XCTAssertGreaterThanOrEqual(reps, 8, "Subtle vibration should still be detected")
        XCTAssertLessThanOrEqual(reps, 12)
    }

    func testRisingAmplitudeStillCounted() {
        // 1 Hz sine, amplitude ramps 0.1 g → 1.0 g over 10 cycles (10 s).
        let samples = SignalGenerators.sineRamp(frequency: 1.0, a0: 0.1, a1: 1.0, duration: 10.0)
        let reps = repCount(runDetector(on: samples))
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }
```

- [ ] **Step 2: Run tests**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | tail -30
```

Expected: all tests pass. If `testSubtleVibrationOnNoise` fails (count too low), lower `thresholdK` toward 0.4 or `noiseFloor` toward 0.015. If `testPureNoiseProducesNoReps` fails (false positives), raise `thresholdK` or `noiseFloor`. Iterate until both pass without breaking the clean-sine tests.

- [ ] **Step 3: Commit**

```bash
git add RepCounterTests/RepDetectorTests.swift "RepCounter Watch App/Detection/RepDetector.swift"
git commit -m "test: noise rejection and subtle vibration detection"
```

---

## Task 7: RepDetector — set-end detection

**Files:**
- Modify: `RepCounterTests/RepDetectorTests.swift`

- [ ] **Step 1: Add failing test**

Append to the test class:

```swift
    func testSetEndsAfterMotionStops() {
        // 1 Hz sine for 10 s, then 6 s of silence. Expect a setEnded event within ~4 s of motion stopping.
        let active = SignalGenerators.sine(frequency: 1.0, amplitude: 0.5, duration: 10.0)
        let lastT = active.last!.timestamp
        let quiet = SignalGenerators.silence(duration: 6.0, startTime: lastT + SignalGenerators.dt)
        let samples = active + quiet

        let detector = RepDetector(sampleRate: 50)
        var setEndTime: TimeInterval? = nil
        var setEndCount: Int? = nil
        detector.onEvent = { event in
            if case .setEnded(let c) = event {
                // Capture the first set-end event only.
                if setEndTime == nil {
                    setEndCount = c
                }
            }
        }
        // Track when we observed the set-end (use the timestamp of the sample being processed).
        for s in samples {
            detector.process(s)
            if setEndTime == nil, let c = setEndCount, c > 0 {
                setEndTime = s.timestamp
            }
        }

        XCTAssertNotNil(setEndTime, "Expected a setEnded event after motion stopped")
        XCTAssertGreaterThanOrEqual(setEndCount ?? 0, 9)
        XCTAssertLessThanOrEqual(setEndCount ?? 0, 11)
        let delay = (setEndTime ?? 0) - lastT
        XCTAssertGreaterThan(delay, 3.5, "Set-end should not fire too eagerly")
        XCTAssertLessThan(delay, 5.5, "Set-end should fire within ~4 s of motion stopping")
    }
```

- [ ] **Step 2: Run tests and verify all pass**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | tail -20
```

Expected: pass. If set-end fires too late, the env may not have dropped to 30% of peak — verify by reducing `setEndEnvDropFraction` to e.g. 0.4.

- [ ] **Step 3: Commit**

```bash
git add RepCounterTests/RepDetectorTests.swift "RepCounter Watch App/Detection/RepDetector.swift"
git commit -m "test: set-end detection after motion stops"
```

---

## Task 8: RepDetector — impact suppression & refractory

**Files:**
- Modify: `RepCounterTests/RepDetectorTests.swift`

- [ ] **Step 1: Add failing tests**

Append to the test class:

```swift
    func testSingleImpactSpikeIgnored() {
        // Flat zero for 5 s with one 3 g spike at t=2 s.
        var samples = SignalGenerators.silence(duration: 5.0)
        let spikeIdx = Int(2.0 * SignalGenerators.sampleRate)
        samples[spikeIdx] = MotionSample(
            timestamp: samples[spikeIdx].timestamp,
            accel: SIMD3(3.0, 0, 0),
            gyro: SIMD3(0, 0, 0)
        )
        let reps = repCount(runDetector(on: samples))
        XCTAssertEqual(reps, 0, "A single impact spike must not be counted")
    }

    func testRefractoryPreventsDoubleCount() {
        // 1 Hz primary sine with a small secondary bump 100 ms after each peak.
        // We emulate this by combining 1 Hz at 0.5 g with 1 Hz at 0.2 g phase-shifted by 100 ms (= 0.1 × 2π = 0.628 rad).
        let n = Int(10.0 * SignalGenerators.sampleRate)
        let samples: [MotionSample] = (0..<n).map { i in
            let t = Double(i) * SignalGenerators.dt
            let v = 0.5 * sin(2 * .pi * 1.0 * t)
                  + 0.2 * sin(2 * .pi * 1.0 * t - 0.628)
            return MotionSample(timestamp: t, accel: SIMD3(v, 0, 0), gyro: SIMD3(0, 0, 0))
        }
        let reps = repCount(runDetector(on: samples))
        // ~10 cycles, expect 9–11 — not 18–20.
        XCTAssertGreaterThanOrEqual(reps, 9)
        XCTAssertLessThanOrEqual(reps, 11)
    }
```

- [ ] **Step 2: Run tests**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | tail -20
```

Expected: both pass. If `testSingleImpactSpikeIgnored` fails, the impact-detection threshold may be too lax — try lowering `impactRatio` to 4.0 or extending `impactSuppressSeconds` to 0.5.

- [ ] **Step 3: Commit**

```bash
git add RepCounterTests/RepDetectorTests.swift "RepCounter Watch App/Detection/RepDetector.swift"
git commit -m "test: impact suppression and refractory double-count prevention"
```

---

## Task 9: Recorded-trace replay infrastructure

**Files:**
- Create: `RepCounterTests/TraceReplayTests.swift`
- Create: `RepCounterTests/traces/.gitkeep`

Sets up the replay harness for traces that will be recorded during manual testing in Task 14. Tests are skipped when no traces are present, so CI stays green.

- [ ] **Step 1: Create the trace folder**

```bash
mkdir -p RepCounterTests/traces
touch RepCounterTests/traces/.gitkeep
```

- [ ] **Step 2: Create TraceReplayTests**

```swift
import XCTest
@testable import RepCounter_Watch_App

/// Replays recorded traces (JSON arrays of [t, ax, ay, az, gx, gy, gz]) through RepDetector
/// and checks the rep count against the file's metadata.
final class TraceReplayTests: XCTestCase {

    struct TraceFile: Decodable {
        let expected_reps: [Int]   // per set
        let samples: [[Double]]    // each row: [t, ax, ay, az, gx, gy, gz]
    }

    private func traceURLs() -> [URL] {
        let bundle = Bundle(for: TraceReplayTests.self)
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "traces") else {
            return []
        }
        return urls
    }

    func testAllRecordedTraces() throws {
        let urls = traceURLs()
        try XCTSkipIf(urls.isEmpty, "No recorded traces present — add JSON files to RepCounterTests/traces/")
        for url in urls {
            let data = try Data(contentsOf: url)
            let trace = try JSONDecoder().decode(TraceFile.self, from: data)
            let detector = RepDetector(sampleRate: 50)
            var setCounts: [Int] = []
            detector.onEvent = { event in
                if case .setEnded(let c) = event { setCounts.append(c) }
            }
            for row in trace.samples {
                let sample = MotionSample(
                    timestamp: row[0],
                    accel: SIMD3(row[1], row[2], row[3]),
                    gyro: SIMD3(row[4], row[5], row[6])
                )
                detector.process(sample)
            }
            // Compare each set ±1.
            XCTAssertEqual(setCounts.count, trace.expected_reps.count,
                           "Trace \(url.lastPathComponent): wrong number of sets detected")
            for (i, (got, want)) in zip(setCounts, trace.expected_reps).enumerated() {
                XCTAssertLessThanOrEqual(abs(got - want), 1,
                    "Trace \(url.lastPathComponent) set \(i+1): expected \(want), got \(got)")
            }
        }
    }
}
```

Add file to `RepCounterTests` target. In Xcode, add the `traces/` folder as a **Folder Reference** (blue folder, not yellow group) under the test target so JSON files ship with the test bundle.

- [ ] **Step 3: Run tests**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | tail -10
```

Expected: trace test is skipped (no traces present); all other tests pass.

- [ ] **Step 4: Commit**

```bash
git add RepCounterTests/TraceReplayTests.swift RepCounterTests/traces/.gitkeep RepCounter.xcodeproj
git commit -m "test: add recorded-trace replay harness"
```

---

## Task 10: MotionSampler — CoreMotion wrapper

**Files:**
- Create: `RepCounter Watch App/Motion/MotionSampler.swift`

No unit tests — this is glue around `CMMotionManager` and can only be meaningfully verified on a real device. It's intentionally thin so almost all logic lives in `RepDetector` (which is tested).

- [ ] **Step 1: Create MotionSampler**

```swift
import Foundation
import CoreMotion
import simd

/// Streams CoreMotion device-motion samples at 50 Hz to a callback.
final class MotionSampler {

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    /// Called on `queue` for each sample.
    var onSample: ((MotionSample) -> Void)?

    init() {
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        queue.name = "RepCounter.MotionSampler"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let sample = MotionSample(
                timestamp: motion.timestamp,
                accel: SIMD3(motion.userAcceleration.x,
                             motion.userAcceleration.y,
                             motion.userAcceleration.z),
                gyro: SIMD3(motion.rotationRate.x,
                            motion.rotationRate.y,
                            motion.rotationRate.z)
            )
            self.onSample?(sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
```

Add to `RepCounter Watch App` target.

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add "RepCounter Watch App/Motion/MotionSampler.swift" RepCounter.xcodeproj
git commit -m "feat: add CoreMotion wrapper for 50 Hz device-motion sampling"
```

---

## Task 11: WorkoutSession — HealthKit + orchestration

**Files:**
- Create: `RepCounter Watch App/Session/WorkoutSession.swift`

Orchestrates the HK workout session, motion sampler, detector, haptics, and observable UI state. Not unit-tested (HKWorkoutSession requires a device); manual verification in Task 14.

- [ ] **Step 1: Create WorkoutSession**

Create folder `Session/`. Create `Session/WorkoutSession.swift`:

```swift
import Foundation
import HealthKit
import WatchKit
import Observation

@Observable
final class WorkoutSession: NSObject {

    enum Phase {
        case idle
        case requestingAuth
        case authDenied
        case active
        case paused
    }

    // MARK: Observable state
    var phase: Phase = .idle
    var currentSetReps: Int = 0
    var lastSetReps: Int? = nil
    var setNumber: Int = 1

    // MARK: Internals
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private let sampler = MotionSampler()
    private let detector = RepDetector(sampleRate: 50)

    override init() {
        super.init()
        sampler.onSample = { [weak self] sample in
            self?.detector.process(sample)
        }
        detector.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDetectorEvent(event)
            }
        }
    }

    // MARK: Public actions

    func start() {
        guard phase == .idle else { return }
        phase = .requestingAuth
        let types: Set = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: types, read: []) { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                if !granted {
                    self.phase = .authDenied
                    return
                }
                self.beginWorkout()
            }
        }
    }

    func pause() {
        guard phase == .active else { return }
        sampler.stop()
        workoutSession?.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        detector.reset()
        workoutSession?.resume()
        sampler.start()
        phase = .active
    }

    func end() {
        sampler.stop()
        workoutBuilder?.endCollection(withEnd: Date()) { _, _ in }
        workoutSession?.end()
        workoutBuilder?.finishWorkout { _, _ in }
        workoutSession = nil
        workoutBuilder = nil
        phase = .idle
        currentSetReps = 0
        lastSetReps = nil
        setNumber = 1
        detector.reset()
    }

    // MARK: Private

    @MainActor
    private func beginWorkout() {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            self.workoutSession = session
            self.workoutBuilder = builder
            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }
            sampler.start()
            phase = .active
        } catch {
            phase = .authDenied
        }
    }

    @MainActor
    private func handleDetectorEvent(_ event: DetectorEvent) {
        switch event {
        case .rep:
            currentSetReps += 1
            WKInterfaceDevice.current().play(.click)
        case .setEnded(let count):
            lastSetReps = count
            setNumber += 1
            currentSetReps = 0
            WKInterfaceDevice.current().play(.success)
        }
    }
}
```

Add to `RepCounter Watch App` target.

- [ ] **Step 2: Add HealthKit capability**

In Xcode: select the `RepCounter Watch App` target → Signing & Capabilities → "+" → HealthKit. Do **not** check "Clinical Health Records".

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add "RepCounter Watch App/Session/WorkoutSession.swift" RepCounter.xcodeproj "RepCounter Watch App/RepCounter Watch App.entitlements" 2>/dev/null
git commit -m "feat: WorkoutSession orchestrating HealthKit, motion, and detection"
```

---

## Task 12: Info.plist permission strings

**Files:**
- Modify: `RepCounter Watch App/Info.plist`

- [ ] **Step 1: Add usage descriptions**

In Xcode, select the `RepCounter Watch App` target → Info tab. Add these keys (or edit the underlying Info.plist):

| Key | Type | Value |
|---|---|---|
| `NSMotionUsageDescription` | String | `RepCounter uses motion sensors to detect and count your workout reps automatically.` |
| `NSHealthShareUsageDescription` | String | `RepCounter records your workouts so they appear in the Fitness app.` |
| `NSHealthUpdateUsageDescription` | String | `RepCounter saves your strength workouts to Health.` |
| `WKBackgroundModes` | Array | One item: `workout-processing` |

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add "RepCounter Watch App/Info.plist" RepCounter.xcodeproj
git commit -m "feat: declare motion and health permissions"
```

---

## Task 13: WorkoutView — full UI

**Files:**
- Modify: `RepCounter Watch App/Views/WorkoutView.swift`

- [ ] **Step 1: Replace WorkoutView with the full implementation**

Open `RepCounter Watch App/Views/WorkoutView.swift` and replace its contents with:

```swift
import SwiftUI

struct WorkoutView: View {
    @State private var session = WorkoutSession()
    @State private var repPulse = false

    var body: some View {
        ZStack {
            switch session.phase {
            case .idle, .requestingAuth:
                idleView
            case .authDenied:
                deniedView
            case .active, .paused:
                activeView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .onChange(of: session.currentSetReps) { _, _ in
            repPulse.toggle()
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Text("RepCounter")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                session.start()
            } label: {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }

    private var deniedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("RepCounter needs Health access to run workouts.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Reset") { session.phase = .idle }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 8)
    }

    private var activeView: some View {
        VStack(spacing: 6) {
            Text("Set \(session.setNumber)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(session.currentSetReps)")
                .font(.system(size: 80, weight: .bold, design: .monospaced))
                .scaleEffect(repPulse ? 1.08 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.5), value: repPulse)
                .opacity(session.phase == .paused ? 0.4 : 1.0)

            if let last = session.lastSetReps {
                Text("Last set: \(last)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 10) {
                Button {
                    if session.phase == .paused {
                        session.resume()
                    } else {
                        session.pause()
                    }
                } label: {
                    Image(systemName: session.phase == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    session.end()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WorkoutView()
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Visual check in simulator**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  -derivedDataPath ./build run 2>&1 | tail -5
```

Open the watchOS simulator, confirm the Idle screen renders with a "Start Workout" button. (Simulator can't run a real workout — that's Task 14.)

- [ ] **Step 4: Commit**

```bash
git add "RepCounter Watch App/Views/WorkoutView.swift"
git commit -m "feat: complete WorkoutView with idle/active/paused states"
```

---

## Task 14: On-device verification & trace recording

**Files:**
- Modify: `RepCounter Watch App/Session/WorkoutSession.swift` (optional debug recording)
- Add: `RepCounterTests/traces/*.json`

This task validates the spec's manual checklist on a real Apple Watch and captures real-world traces so the test suite can replay them.

- [ ] **Step 1: Run the manual checklist on device**

Pair an Apple Watch Series 6+ running watchOS 10+, build & run via Xcode (Product → Run with the watch as the destination). Walk through each item:

- [ ] Bench press 3×10 — counts within ±1 per set
- [ ] Back squat 3×5 — counts within ±1 (this is the vibration-only case)
- [ ] Bicep curl 3×12 — counts within ±1
- [ ] Walking around / no workout for 60 s — produces no false reps
- [ ] Workout appears in the Fitness app afterward
- [ ] Per-rep haptic timing feels in sync (not noticeably lagging)
- [ ] App stays running with wrist down / screen off (HK session keeps it alive)

- [ ] **Step 2: Add debug trace recording (optional but recommended)**

If any of the above misses reps, add temporary recording. In `WorkoutSession.swift`, inside `init()`, append after the existing `sampler.onSample` assignment:

```swift
#if DEBUG
        var recorded: [[Double]] = []
        sampler.onSample = { [weak self] sample in
            recorded.append([sample.timestamp,
                             sample.accel.x, sample.accel.y, sample.accel.z,
                             sample.gyro.x, sample.gyro.y, sample.gyro.z])
            self?.detector.process(sample)
            if recorded.count % 500 == 0 {
                // Periodically save to Application Support.
                if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let file = url.appendingPathComponent("trace.json")
                    if let data = try? JSONSerialization.data(withJSONObject: recorded) {
                        try? data.write(to: file)
                    }
                }
            }
        }
#endif
```

Use the Xcode Devices window to copy `trace.json` off the watch after a workout, manually wrap it in the `TraceFile` JSON format (`{"expected_reps": [N1, N2, ...], "samples": [...]}`) with the ground-truth rep counts you observed, and drop the file into `RepCounterTests/traces/`.

- [ ] **Step 3: Run the trace replay test**

```bash
xcodebuild -project RepCounter.xcodeproj -scheme "RepCounter Watch App" \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" \
  test 2>&1 | grep -E "(trace|Test Case)"
```

Expected: `TraceReplayTests.testAllRecordedTraces` passes. If a trace fails, the detector's constants need tuning — adjust in `RepDetector.swift` and re-run all tests to confirm no regression on synthetic cases.

- [ ] **Step 4: Remove the debug recording**

Once enough traces are committed, remove the `#if DEBUG` recording block from `WorkoutSession.swift`.

- [ ] **Step 5: Commit**

```bash
git add RepCounterTests/traces/*.json "RepCounter Watch App/Session/WorkoutSession.swift" "RepCounter Watch App/Detection/RepDetector.swift" 2>/dev/null
git commit -m "test: add real-device traces and final detector tuning"
```

---

## Done

When all 14 tasks are checked off, the app meets the v1 spec: starts a HealthKit-backed workout, auto-counts reps from wrist motion with adaptive thresholding (including subtle leg-day vibrations), auto-ends sets, gives per-rep haptic feedback, and saves the workout to Health.
