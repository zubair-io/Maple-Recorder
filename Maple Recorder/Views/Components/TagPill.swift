import SwiftUI

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(MapleTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(MapleTheme.surfaceAlt, in: .capsule)
    }
}
