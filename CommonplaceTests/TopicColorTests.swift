import Testing

@testable import Commonplace

struct TopicColorTests {
    @Test func paletteHasTheEightDesignColors() {
        #expect(
            TopicColor.allCases
                == [.red, .orange, .brown, .green, .teal, .indigo, .purple, .pink]
        )
    }

    @Test func defaultIsIndigo() {
        #expect(TopicColor.defaultColor == .indigo)
    }

    @Test func retiredRawValuesAreNotCases() {
        #expect(TopicColor(rawValue: "blue") == nil)
        #expect(TopicColor(rawValue: "yellow") == nil)
    }

    @Test func displayNamesAreCapitalized() {
        #expect(TopicColor.indigo.displayName == "Indigo")
        #expect(TopicColor.allCases.map(\.displayName).allSatisfy { !$0.isEmpty })
    }

    @MainActor
    @Test func unknownAndRetiredRawValuesFallBackToIndigo() {
        let topic = Topic()
        for rawValue in ["blue", "yellow", "chartreuse", ""] {
            topic.colorName = rawValue
            #expect(topic.color == .indigo)
        }
    }
}
