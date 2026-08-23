import Foundation
import Testing
@testable import Maple_Recorder

struct AssistContextBuilderTests {
    @Test func includesPreviousAndCurrentTurnInChronologicalOrder() {
        let previousImage = LLMImage(data: Data([0x01]), mediaType: "image/jpeg")
        let currentImage = LLMImage(data: Data([0x02]), mediaType: "image/jpeg")
        let previousTurn = AssistTurnSnapshot(
            recognizedText: "Previous question",
            image: previousImage,
            response: "Previous answer"
        )

        let context = AssistContextBuilder.build(
            currentScreenText: "Current question",
            currentImage: currentImage,
            notes: "Current notes",
            previousTurn: previousTurn,
            characterBudget: 4_000,
            includeImages: true
        )

        #expect(context.userMessage.contains("Previous question"))
        #expect(context.userMessage.contains("Previous answer"))
        #expect(context.userMessage.contains("Current question"))
        #expect(context.userMessage.contains("Current notes"))
        #expect(context.images.map(\.label) == ["Previous screen", "Current screen"])
        #expect(context.images.map(\.data) == [previousImage.data, currentImage.data])
    }

    @Test func cloudImageOptOutStillKeepsTextContinuity() {
        let previousTurn = AssistTurnSnapshot(
            recognizedText: "Previous question",
            image: LLMImage(data: Data([0x01]), mediaType: "image/jpeg"),
            response: "Previous answer"
        )

        let context = AssistContextBuilder.build(
            currentScreenText: "Current question",
            currentImage: LLMImage(data: Data([0x02]), mediaType: "image/jpeg"),
            notes: "",
            previousTurn: previousTurn,
            characterBudget: 4_000,
            includeImages: false
        )

        #expect(context.images.isEmpty)
        #expect(context.userMessage.contains("Previous question"))
        #expect(context.userMessage.contains("Previous answer"))
        #expect(context.userMessage.contains("No notes yet."))
    }
}
