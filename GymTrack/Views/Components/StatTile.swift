import SwiftUI

struct StatTile: View {
    let title: String
    let value: String
    let caption: String?
    var tint: Color = Theme.accent
    var systemImage: String

    init(title: String, value: String, caption: String? = nil, tint: Color = Theme.accent, systemImage: String) {
        self.title = title
        self.value = value
        self.caption = caption
        self.tint = tint
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        )
    }
}
