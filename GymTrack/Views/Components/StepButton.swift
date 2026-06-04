import SwiftUI

struct StepButton: View {
    let symbol: String
    var accessibilityLabel: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel.isEmpty ? Text(symbol) : Text(accessibilityLabel))
    }
}
