import SwiftUI

/// A pill-shaped toggle button used for opt-in recording options (system audio,
/// video). Replaces the platform-native `.checkbox` toggle style so options stay
/// visually consistent across macOS and iOS, since iOS has no equivalent native style.
struct RecordingOptionChip: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(isOn ? .white : MapleTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? MapleTheme.primary : MapleTheme.surfaceAlt, in: .capsule)
                .overlay {
                    if !isOn {
                        Capsule().stroke(MapleTheme.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
