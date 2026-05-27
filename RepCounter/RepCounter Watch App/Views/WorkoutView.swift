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
