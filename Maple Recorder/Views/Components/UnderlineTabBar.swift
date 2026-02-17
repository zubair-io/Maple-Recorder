import SwiftUI

struct UnderlineTabBar<Selection: Hashable>: View {
    @Binding var selection: Selection
    let tabs: [(label: String, value: Selection)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = tab.value
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.label)
                                .font(.subheadline)
                                .fontWeight(selection == tab.value ? .semibold : .regular)
                                .foregroundStyle(
                                    selection == tab.value
                                        ? MapleTheme.primary
                                        : MapleTheme.textSecondary.opacity(0.7)
                                )

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(selection == tab.value ? MapleTheme.primary : Color.clear)
                                .frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }

            Rectangle()
                .fill(MapleTheme.border.opacity(0.1))
                .frame(height: 1)
        }
    }
}
