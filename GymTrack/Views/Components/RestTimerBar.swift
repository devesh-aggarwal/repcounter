import SwiftUI

struct RestTimerBar: View {
    @ObservedObject var timer: RestTimer

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: timer.finished ? 1 : timer.progress)
                    .stroke(timer.finished ? Theme.accent : Theme.accentSoft,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: timer.progress)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(timer.finished ? "Rest complete" : timer.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(timer.finished ? "Let's go" : timer.display)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }

            Spacer()

            if timer.finished {
                controlButton("checkmark", filled: true) { timer.stop() }
            } else {
                controlButton("minus") { timer.adjust(by: -15) }
                controlButton(timer.isPaused ? "play.fill" : "pause.fill") { timer.togglePause() }
                controlButton("plus") { timer.adjust(by: 15) }
                controlButton("xmark") { timer.stop() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surfaceElevated)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        )
    }

    private var icon: String {
        if timer.finished { return "checkmark" }
        return timer.isPaused ? "pause.fill" : "timer"
    }

    private func controlButton(_ symbol: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? .black : Theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.08)))
                )
        }
        .buttonStyle(.plain)
    }
}
