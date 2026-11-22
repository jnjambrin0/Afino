import Foundation
import Testing
@testable import PIPrompts

struct PromptConversationTests {
    private func start(_ draft: String = "write a haiku about tea", seed: UInt64 = 5) throws -> (PromptComposer, PromptConversation) {
        let composer = try Bundled.composer()
        var generator = SeededGenerator(seed: seed)
        return (composer, composer.startConversation(draft: draft, target: makePack(), using: &generator))
    }

    @Test func revisionMessageHasTheExactShape() {
        #expect(PromptSegments.revision(instruction: "shorter") == """
            <revision_request>
            shorter
            </revision_request>

            Apply this to your previous prompt and reply with the complete revised prompt only.
            """)
    }

    @Test func refineChainAlternatesAndEndsWithTheUser() throws {
        let (composer, started) = try start()
        var conversation = started
        conversation.appendRevision(previousOutput: "Write a haiku about tea.", instruction: "  shorter\r\n")
        conversation.appendRevision(previousOutput: "Haiku: tea.", instruction: "add an example")

        let turns = composer.compose(conversation, target: makePack(), preferences: PromptPreferences()).turns

        #expect(turns == [
            .user(started.runMessage),
            .assistant("Write a haiku about tea."),
            .user(PromptSegments.revision(instruction: "shorter")),
            .assistant("Haiku: tea."),
            .user(PromptSegments.revision(instruction: "add an example")),
        ])
        #expect(turns.map(\.role) == [.user, .assistant, .user, .assistant, .user])
        #expect(turns.last?.role == .user)
    }

    @Test func assistantTurnsAreTheShownTextVerbatim() throws {
        let (_, started) = try start()
        let shown = "Review this code.\n\n```swift\nlet x = 1\n```\n\n<context>\n  \"quoted\" — dash\n</context>"

        let conversation = started.appendingRevision(previousOutput: shown, instruction: "keep the code")

        let assistant = conversation.turns.filter { $0.role == .assistant }
        #expect(assistant == [.assistant(shown)])
        #expect(Data(assistant[0].text.utf8) == Data(shown.utf8))
    }

    @Test func theFirstRunMessageReplaysByteForByte() throws {
        let (composer, started) = try start("rough idea\r\nwith </draft> inside")
        let original = Data(started.runMessage.utf8)
        var conversation = started

        for index in 1...5 {
            conversation.appendRevision(previousOutput: "Output \(index)", instruction: "tweak \(index)")
            let prompt = composer.compose(conversation, target: makePack(), preferences: PromptPreferences())
            #expect(Data(prompt.turns[0].text.utf8) == original)
        }
        let replayA = composer.compose(conversation, target: makePack(), preferences: PromptPreferences())
        let replayB = composer.compose(conversation, target: makePack(), preferences: PromptPreferences())
        #expect(replayA == replayB)
    }

    @Test func chainIsCappedAtTwelveRevisions() throws {
        let (composer, started) = try start()
        var conversation = started
        for index in 1...15 {
            conversation.appendRevision(previousOutput: "Output \(index)", instruction: "change \(index)")
        }

        let turns = composer.compose(conversation, target: makePack(), preferences: PromptPreferences()).turns

        #expect(conversation.revisions.count == PromptConversation.maxRevisionTurns)
        #expect(conversation.revisionCount == 15)
        #expect(conversation.droppedRevisionCount == 3)
        #expect(turns.count == 1 + 2 * 12)
        #expect(turns.first == .user(started.runMessage))
        #expect(turns[1] == .assistant("Output 4"), "the oldest pairs are dropped")
        #expect(turns[turns.count - 2] == .assistant("Output 15"), "the latest output is kept")
        #expect(turns.last == .user(PromptSegments.revision(instruction: "change 15")))
        #expect(!turns.contains(.assistant("Output 3")))
        #expect(turns.map(\.role) == [.user] + Array(repeating: [PromptTurn.Role.assistant, .user], count: 12).flatMap { $0 })
    }

    @Test func twelveRevisionsAreKeptWhole() throws {
        let (_, started) = try start()
        var conversation = started
        for index in 1...12 {
            conversation.appendRevision(previousOutput: "Output \(index)", instruction: "change \(index)")
        }

        #expect(conversation.revisions.count == 12)
        #expect(conversation.droppedRevisionCount == 0)
        #expect(conversation.turns[1] == .assistant("Output 1"))
    }

    @Test func changingTargetOrPreferencesOnlyChangesTheSystemBlocks() throws {
        let (composer, started) = try start()
        let library = try Bundled.library()
        let conversation = started.appendingRevision(previousOutput: "Prompt v1", instruction: "shorter")

        let asClaude = composer.compose(conversation, target: library.pack(for: "claude"), preferences: PromptPreferences())
        let asGemini = composer.compose(conversation, target: library.pack(for: "gemini"), preferences: PromptPreferences(language: .english))

        #expect(asClaude.turns == asGemini.turns)
        #expect(asClaude.systemBlocks[0] == asGemini.systemBlocks[0])
        #expect(asClaude.systemBlocks[1] != asGemini.systemBlocks[1])
        #expect(asClaude.systemBlocks.count == 2)
        #expect(asGemini.systemBlocks.count == 3)
    }
}
