import SwiftUI

struct TranscriptRowView: View {
    let segment: TranscriptSegment
    let speaker: Speaker?
    let isActive: Bool
    let activeWordId: UUID?
    var onTapWord: ((WordTiming) -> Void)?
    var onTapSpeaker: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(speakerColor)
                .frame(width: 3)
                .padding(.trailing, 8)

            // Timestamp + speaker name
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTimestamp(segment.start))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MapleTheme.textSecondary)

                Button {
                    onTapSpeaker?()
                } label: {
                    Text(speaker?.displayName ?? segment.speakerId)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(speakerColor)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 70, alignment: .trailing)
            .padding(.trailing, 10)

            // Word-level text with flow layout
            FlowLayout(spacing: 0) {
                ForEach(segment.words) { word in
                    Text(word.word + " ")
                        .font(.body)
                        .foregroundStyle(MapleTheme.textPrimary)
                        .padding(.vertical, 1)
                        .background(
                            word.id == activeWordId
                                ? MapleTheme.primary.opacity(0.25)
                                : Color.clear,
                            in: .rect(cornerRadius: 3)
                        )
                        .onTapGesture {
                            onTapWord?(word)
                        }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isActive ? MapleTheme.primaryLight.opacity(0.15) : Color.clear,
            in: .rect(cornerRadius: 8)
        )
    }

    private var speakerColor: Color {
        if let speaker {
            Color(speaker.color)
        } else {
            MapleTheme.primary
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
