import SwiftUI

/// A one-shot confetti burst. Pass `trigger` and bump its value to fire a
/// fresh burst. Self-cleans after the animation completes.
struct Confetti: View {
    let trigger: Int

    @State private var pieces: [ConfettiPiece] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Rectangle()
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(piece.rotation))
                        .position(x: piece.x, y: piece.y)
                        .opacity(piece.opacity)
                }
            }
            .onChange(of: trigger) { _, _ in
                burst(in: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func burst(in size: CGSize) {
        let palette: [Color] = [
            Color(hex: "#FFD740"), Color(hex: "#FF6E40"), Color(hex: "#00E676"),
            Color(hex: "#40C4FF"), Color(hex: "#BF5AF2"), Color(hex: "#FF375F"),
            Color(hex: "#FFFFFF")
        ]
        var fresh: [ConfettiPiece] = []
        for _ in 0..<48 {
            let startX = CGFloat.random(in: 0...size.width)
            fresh.append(
                ConfettiPiece(
                    color: palette.randomElement() ?? .yellow,
                    width: CGFloat.random(in: 6...10),
                    height: CGFloat.random(in: 10...16),
                    x: startX,
                    y: -30,
                    rotation: Double.random(in: 0...360),
                    opacity: 1
                )
            )
        }
        pieces = fresh

        // Animate each piece falling + rotating.
        for index in pieces.indices {
            let dx = CGFloat.random(in: -90...90)
            let dur = Double.random(in: 1.4...2.2)
            withAnimation(.easeIn(duration: dur)) {
                pieces[index].x += dx
                pieces[index].y = size.height + 60
                pieces[index].rotation += Double.random(in: 360...1080)
            }
            withAnimation(.easeIn(duration: dur).delay(dur - 0.35)) {
                pieces[index].opacity = 0
            }
        }

        // Clear after the last piece settles.
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run { pieces = [] }
        }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    var color: Color
    var width: CGFloat
    var height: CGFloat
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var opacity: Double
}
