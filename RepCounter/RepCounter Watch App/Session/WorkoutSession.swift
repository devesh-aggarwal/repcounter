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
        healthStore.requestAuthorization(toShare: types, read: []) { granted, _ in
            Task { @MainActor [weak self] in
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
