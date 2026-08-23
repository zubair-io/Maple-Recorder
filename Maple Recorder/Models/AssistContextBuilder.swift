#if !os(watchOS)
import Foundation

struct AssistTurnSnapshot: Sendable {
    let recognizedText: String
    let image: LLMImage?
    let response: String
}

struct AssistRequestContext: Sendable {
    let userMessage: String
    let images: [LLMImage]
}

enum AssistContextBuilder {
    static func build(
        currentScreenText: String,
        currentImage: LLMImage?,
        notes: String,
        previousTurn: AssistTurnSnapshot?,
        characterBudget: Int,
        includeImages: Bool
    ) -> AssistRequestContext {
        let hasPreviousTurn = previousTurn != nil
        let currentScreenBudget = Int(Double(characterBudget) * (hasPreviousTurn ? 0.45 : 0.7))
        let notesBudget = Int(Double(characterBudget) * (hasPreviousTurn ? 0.25 : 0.3))
        let previousScreenBudget = Int(Double(characterBudget) * 0.2)
        let previousResponseBudget = max(
            0,
            characterBudget - currentScreenBudget - notesBudget - previousScreenBudget
        )
        let visibleScreen = String(currentScreenText.prefix(currentScreenBudget))
        let recentNotes = String(notes.suffix(notesBudget))

        let previousContext: String
        if let previousTurn {
            previousContext = """
                Use the previous turn only for continuity; prioritize the current screen and notes.

                Previous visible screen text:
                ---
                \(String(previousTurn.recognizedText.prefix(previousScreenBudget)))
                ---

                Previous suggested response:
                ---
                \(String(previousTurn.response.suffix(previousResponseBudget)))
                ---

                """
        } else {
            previousContext = ""
        }

        var images: [LLMImage] = []
        if includeImages, let previousImage = previousTurn?.image {
            images.append(
                LLMImage(
                    data: previousImage.data,
                    mediaType: previousImage.mediaType,
                    label: "Previous screen"
                )
            )
        }
        if includeImages, let currentImage {
            images.append(
                LLMImage(
                    data: currentImage.data,
                    mediaType: currentImage.mediaType,
                    label: "Current screen"
                )
            )
        }

        return AssistRequestContext(
            userMessage: """
                \(previousContext)Current visible screen text:
                ---
                \(visibleScreen)
                ---

                Presenter's current notes:
                ---
                \(recentNotes.isEmpty ? "No notes yet." : recentNotes)
                ---
                """,
            images: images
        )
    }
}
#endif
