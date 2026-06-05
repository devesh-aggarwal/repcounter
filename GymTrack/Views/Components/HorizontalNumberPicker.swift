import SwiftUI

/// Horizontal number picker — a row of numeric labels (one per `step`) where
/// the centered value is bright white and the others fade outward by
/// distance. The bright number IS the indicator; alignment is intrinsic.
struct HorizontalNumberPicker: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    var onCommit: () -> Void = {}

    @State private var scrollPositionID: Double?
    @State private var commitTask: Task<Void, Never>?
    @State private var lastSnappedValue: Double = 0

    /// Width allotted per number. Wide enough that "37.5" doesn't crowd, tight
    /// enough that several values stay visible on either side of center.
    private let itemWidth: CGFloat = 58

    private var allValues: [Double] {
        var values: [Double] = []
        var current = range.lowerBound
        while current <= range.upperBound + 0.0001 {
            values.append((current * 10).rounded() / 10)
            current += step
        }
        return values
    }

    var body: some View {
        GeometryReader { geo in
            // Pad both ends so the first and last values can snap to the
            // viewport's center. Without this, a `.scrollPosition(anchor: .center)`
            // on an edge item gets clamped to the scroll edge and the
            // brightest number lands off-center after the first scroll.
            let inset = max(0, (geo.size.width - itemWidth) / 2)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(allValues, id: \.self) { val in
                        numberLabel(for: val)
                            .frame(width: itemWidth, height: 50)
                            .id(val)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPositionID, anchor: .center)
            .scrollClipDisabled()
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .overlay(alignment: .bottom) { centerUnderline }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.18),
                        .init(color: .white, location: 0.82),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .frame(height: 58)
        .onChange(of: scrollPositionID) { _, newValue in
            handleScroll(to: newValue)
        }
        .onAppear {
            lastSnappedValue = value
            Task { @MainActor in
                scrollPositionID = nearestStep(to: value)
            }
        }
        .onChange(of: value) { _, newValue in
            let snapped = nearestStep(to: newValue)
            if snapped != scrollPositionID {
                scrollPositionID = snapped
                lastSnappedValue = snapped
            }
        }
    }

    // MARK: Drawing

    private func numberLabel(for val: Double) -> some View {
        let stepsAway = abs(val - value) / max(step, 0.001)
        // Center = 1.0, ±1 step = 0.62, ±2 = 0.4, fades to floor 0.18.
        let opacity = max(0.18, 1.0 - stepsAway * 0.22)
        let isCenter = stepsAway < 0.5

        return Text(val.clean)
            .font(.system(
                size: isCenter ? 19 : 16,
                weight: isCenter ? .bold : .medium,
                design: .rounded
            ))
            .foregroundStyle(
                isCenter ? Theme.textPrimary : Theme.textPrimary.opacity(opacity)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.22), value: value)
    }

    /// Subtle tint-colored underline beneath the centered number — confirms
    /// alignment for users who want a positional cue beyond brightness.
    private var centerUnderline: some View {
        Capsule()
            .fill(tint)
            .frame(width: 26, height: 3)
            .shadow(color: tint.opacity(0.6), radius: 6)
            .padding(.bottom, 4)
            .allowsHitTesting(false)
    }

    // MARK: Behavior

    private func nearestStep(to target: Double) -> Double {
        let stepped = (target / step).rounded() * step
        let clamped = min(max(range.lowerBound, stepped), range.upperBound)
        return (clamped * 10).rounded() / 10
    }

    private func handleScroll(to newValue: Double?) {
        guard let newValue else { return }
        if abs(newValue - lastSnappedValue) >= step * 0.5 {
            lastSnappedValue = newValue
            Haptics.tick()
        }
        if value != newValue {
            value = newValue
        }

        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            if !Task.isCancelled {
                await MainActor.run { onCommit() }
            }
        }
    }
}
