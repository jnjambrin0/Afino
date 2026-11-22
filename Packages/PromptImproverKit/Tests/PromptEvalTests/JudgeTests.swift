import Foundation
import PIPrompts
import PIProviders
import Testing
@testable import PromptEval

/// The rubric judge: what it is shown, and how leniently its reply is read.
struct JudgeTests {
    @Test
    func aStrictReplyParses() throws {
        let parsed = try RubricJudge.parse(judgeReply(overall: 4, failing: ["proportionate"])).get()
        #expect(parsed.overall == 4)
        #expect(parsed.criteria.count == RubricJudge.criteria.count)
        #expect(parsed.criteria["proportionate"]?.passed == false)
        #expect(parsed.criteria["clean_output"] == CriterionVerdict(passed: true, reason: "scripted"))
    }

    @Test
    func aLooseReplyStillParses() throws {
        let fenced = "Here is my grading:\n```json\n" + judgeReply(overall: 5) + "\n```\nThanks."
        #expect(try RubricJudge.parse(fenced).get().overall == 5)

        var loose: [String] = RubricJudge.criteria.map { "\"\($0)\": true" }
        loose[0] = "\"is_a_prompt_not_an_answer\": \"yes\""
        loose[1] = "\"intent_preserved\": {\"passed\": \"false\", \"reason\": \"dropped the audience\"}"
        let parsed = try RubricJudge.parse("{" + loose.joined(separator: ",") + ", \"overall\": \"3.6\"}").get()
        #expect(parsed.overall == 4)
        #expect(parsed.criteria["is_a_prompt_not_an_answer"]?.passed == true)
        #expect(parsed.criteria["intent_preserved"] == CriterionVerdict(passed: false, reason: "dropped the audience"))
    }

    @Test(arguments: [
        "I think this is a good prompt.",
        "{\"is_a_prompt_not_an_answer\": true, \"overall\": 5}",
        String(judgeReply(overall: 9)),
        judgeReply(overall: 5).replacingOccurrences(of: "\"overall\": 5", with: "\"overall\": true"),
    ])
    func anUnusableReplyIsAProblemNotACrash(_ reply: String) {
        guard case .failure(let problem) = RubricJudge.parse(reply) else {
            Issue.record("parsed an unusable reply")
            return
        }
        #expect(!problem.message.isEmpty)
    }

    @Test
    func theJudgeSeesTheMaterialButNeverTheEngineSystemPrompt() throws {
        let fixture = Shipped.fixture("es-email-english")
        let pack = try #require(Shipped.packs.pack(withID: fixture.target))
        let message = RubricJudge.userMessage(draft: fixture.draft, target: pack, preferences: fixture.promptPreferences,
                                              revision: nil, output: "Write a short email in Spanish to my landlord.")
        #expect(message.contains("<original_draft>\n\(fixture.draft)\n</original_draft>"))
        #expect(message.contains(pack.guidance))
        #expect(message.contains(pack.promptLabel))
        #expect(message.contains("<output_to_grade>\nWrite a short email in Spanish to my landlord.\n</output_to_grade>"))
        #expect(message.contains("Write the prompt in English regardless"))
        #expect(!message.contains("revision_requested"))
        for canary in LeakMarkers.canaries {
            #expect(!message.contains(canary))
            #expect(!RubricJudge.systemPrompt.contains(canary))
        }
        let request = RubricJudge.request(model: .anthropic, userMessage: message)
        #expect(request.systemBlocks == [RubricJudge.systemPrompt])
        #expect(request.turns == [.user(message)])
        #expect(request.model == "claude-opus-5-5")
        #expect(request.effort == .medium)

        let revised = RubricJudge.userMessage(draft: "d", target: pack, preferences: PromptPreferences(), revision: "más corto", output: "o")
        #expect(revised.contains("<revision_requested_after_first_rewrite>\nmás corto\n"))
    }

    @Test
    func theSystemPromptNamesEveryCriterionAndTheShape() {
        for name in RubricJudge.criteria {
            #expect(RubricJudge.systemPrompt.contains("\(name):"), "\(name) is explained")
            #expect(RubricJudge.systemPrompt.contains("\"\(name)\": {\"pass\""), "\(name) is in the reply shape")
        }
        #expect(RubricJudge.systemPrompt.contains("\"overall\": 4}"))
    }

    @Test
    func judgeChoiceFollowsTheKeys() {
        #expect(JudgeSetup.make(availableProviders: [.anthropic, .openai]) == JudgeSetup(primary: .anthropic, crossCheck: .openAI))
        #expect(JudgeSetup.make(availableProviders: [.anthropic]) == JudgeSetup(primary: .anthropic, crossCheck: nil))
        #expect(JudgeSetup.make(availableProviders: [.openai]) == JudgeSetup(primary: .openAI, crossCheck: nil))
        #expect(JudgeSetup.make(availableProviders: []) == nil)
    }

    @Test
    func aFailedJudgeRequestIsRecordedNotThrown() async {
        let provider = ScriptedProvider(id: .anthropic) { _ in .failing(EngineFailure(.overloaded, provider: .anthropic, requestID: "req_9")) }
        let verdict = await RubricJudge.grade(model: .anthropic, userMessage: "m", provider: provider, key: APIKey("k"))
        #expect(!verdict.isUsable)
        #expect(verdict.error == "judge request failed: overloaded [request req_9]")

        let garbled = ScriptedProvider(id: .anthropic) { _ in .text("five out of five") }
        let unparsed = await RubricJudge.grade(model: .anthropic, userMessage: "m", provider: garbled, key: APIKey("k"))
        #expect(unparsed.error == "the judge reply is not a JSON object")
        #expect(unparsed.usage != nil)
    }
}
