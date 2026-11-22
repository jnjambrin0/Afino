import Foundation
import Testing
@testable import PromptEval

/// Each check with an output that should pass and one that should not.
struct DeterministicChecksTests {
    typealias Name = DeterministicChecks.Name

    private func results(_ fixtureID: String, _ output: String, previous: String? = nil, draftID: String = "q7x2") -> [CheckResult] {
        DeterministicChecks.run(CheckInput(fixture: Shipped.fixture(fixtureID), output: output, previousOutput: previous, draftID: draftID))
    }

    private func failed(_ results: [CheckResult]) -> Set<String> {
        Set(results.filter { !$0.passed }.map(\.name))
    }

    // MARK: - Whole fixtures

    static let goodEmailPrompt = """
        Redacta un correo breve y educado para mi casero en el que le pida que arregle la caldera, que ha dejado de funcionar. \
        Explica el problema con claridad, pide que la reparación se haga lo antes posible y ofrece facilitar el acceso a la vivienda. \
        Indica [desde cuándo falla la caldera] para dar contexto. El tono debe ser cordial pero firme.
        """

    @Test
    func aGoodPromptPassesEveryCheck() {
        let checks = results("es-email", Self.goodEmailPrompt)
        #expect(failed(checks).isEmpty, "\(checks.filter { !$0.passed })")
        let names = Set(checks.map(\.name))
        #expect(names.isSuperset(of: [Name.completed, Name.noPrefaceOrCommentary, Name.noWrappingFence, Name.mustContain,
                                      Name.mustNotMatch, Name.language, Name.length, Name.codeFences, Name.noLeakage]))
    }

    @Test
    func anEmailInsteadOfAPromptFails() {
        let answer = """
            Asunto: Reparación de la caldera

            Hola Andrés,

            Te escribo porque la caldera ha dejado de funcionar desde el lunes y no tenemos agua caliente. ¿Podrías enviar a alguien para arreglarla esta semana?

            Un saludo,
            Lucía
            """
        #expect(failed(results("es-email", answer)) == [Name.mustNotMatch])
    }

    @Test
    func answeringTheQuestionFails() {
        let checks = results("es-question", "La capital de Australia es Canberra, no Sídney como mucha gente cree.")
        #expect(failed(checks) == [Name.mustNotContain])
    }

    @Test
    func aPromptForTheQuestionPasses() {
        let prompt = "¿Cuál es la capital de Australia? Responde con el nombre de la ciudad y una frase que explique por qué se eligió como capital."
        #expect(failed(results("es-question", prompt)).isEmpty)
    }

    @Test
    func anIncompleteRunReportsOnlyThat() {
        let checks = DeterministicChecks.run(CheckInput(fixture: Shipped.fixture("es-email"), output: "Redacta un", completionFailure: "finished as truncated", draftID: "ab12"))
        #expect(checks == [.fail(Name.completed, "finished as truncated")])
        let empty = DeterministicChecks.run(CheckInput(fixture: Shipped.fixture("es-email"), output: "  \n", draftID: "ab12"))
        #expect(empty.map(\.name) == [Name.completed])
        #expect(empty.first?.passed == false)
    }

    // MARK: - Preface and commentary

    @Test(arguments: [
        "Here's an improved version of your prompt:\n\nExplain Kubernetes to a backend developer who has only used Heroku.",
        "Sure! Explain Kubernetes to a backend developer who has only used Heroku.",
        "Certainly. Explain Kubernetes to a backend developer who has only used Heroku.",
        "Aquí tienes el prompt mejorado:\n\nExplica Kubernetes.",
        "I've rewritten your draft to be clearer.\n\nExplain Kubernetes to a backend developer who has only used Heroku.",
        "**Here is the revised prompt**\n\nExplain Kubernetes.",
    ])
    func prefaceLinesFail(_ output: String) {
        #expect(!DeterministicChecks.prefaceOrCommentary(output, draft: "explain kubernetes").passed)
    }

    @Test(arguments: [
        "Explain Kubernetes to a backend developer who has only used Heroku.\n\nLet me know if you'd like any changes.",
        "Explica Kubernetes a un desarrollador backend.\n\n¿Quieres que lo haga más corto?",
        "Explain Kubernetes.\n\nI hope this helps!",
    ])
    func closingCommentaryFails(_ output: String) {
        #expect(!DeterministicChecks.prefaceOrCommentary(output, draft: "explain kubernetes").passed)
    }

    @Test(arguments: [
        "Here is an article from our company blog:\n\n<article>…</article>\n\n[what you want done with this text]",
        "Claro y conciso: explica Kubernetes a un desarrollador backend.",
        "Explain Kubernetes to a backend developer.\n\nLet me know if you need more context before you start.",
        "Surely you know Heroku; explain how Kubernetes differs.",
    ])
    func promptLinesThatLookChattyPass(_ output: String) {
        #expect(DeterministicChecks.prefaceOrCommentary(output, draft: "explain kubernetes").passed)
    }

    @Test
    func aLineTakenFromTheDraftIsNeverCommentary() {
        let draft = "Here is my improved prompt template:\n\nWrite a haiku."
        #expect(DeterministicChecks.prefaceOrCommentary("Here is my improved prompt template:\n\nWrite a haiku about rain.", draft: draft).passed)
    }

    // MARK: - Fences

    @Test
    func aWhollyFencedOutputFails() {
        let fenced = "```markdown\nExplain Kubernetes to a backend developer who has only used Heroku.\n```"
        #expect(failed(results("en-casual", fenced)).contains(Name.noWrappingFence))
        #expect(!DeterministicChecks.wrappingFence("```\nA prompt.\n```", draft: "a draft").passed)
        #expect(!DeterministicChecks.wrappingFence("~~~~\nA prompt.\n~~~~\n", draft: "a draft").passed)
    }

    @Test
    func aCodeBlockInsideProseIsNotAWrapper() {
        let output = "```swift\nlet a = 1\n```\n\nWhy does this crash?\n\n```\nlog\n```"
        #expect(DeterministicChecks.wrappingFence(output, draft: "a draft").passed)
        #expect(DeterministicChecks.wrappingFence("```\nA prompt.\n```", draft: "```\nmy draft\n```").passed, "the draft itself was fenced")
    }

    @Test
    func codeFencesNeedPermissionAndTheRightCount() {
        let withCode = "Write a Python function that dedupes a list of dicts by key.\n\n```python\ndef dedupe(items, key): ...\n```"
        #expect(failed(results("en-code-short", withCode)).isSuperset(of: [Name.codeFences, Name.mustNotContain]))

        let snippet = Shipped.fixture("en-code-snippet")
        let code = snippet.preserveVerbatim[0]
        let one = "Explain why this Swift function crashes on empty arrays and fix it.\n\n```swift\n\(code)\n```"
        #expect(failed(results("en-code-snippet", one)).isEmpty)
        let two = one + "\n\nExpected:\n\n```\nsummarize([]) returns nil\n```"
        #expect(failed(results("en-code-snippet", two)) == [Name.codeFences])
    }

    // MARK: - Fidelity

    @Test
    func aDroppedVariableFails() {
        let output = "Write a reply to {{customer_name}} about their delayed order. Apologise once, explain that the courier lost the parcel at the regional depot and that a replacement ships within 2 working days at no cost. Keep the tone {{tone}} and the reply under 120 words. Do not offer discount codes."
        let checks = results("vars-mustache", output)
        #expect(failed(checks) == [Name.preservedVerbatim])
        #expect(checks.first { $0.name == Name.preservedVerbatim }?.detail.contains("{{order_id}}") == true)
    }

    @Test
    func anInventedVariableFails() {
        let draft = Shipped.fixture("vars-mustache").draft
        let check = DeterministicChecks.inventedVariables(draft + "\n\nSign off as {{agent_name}}.", draft: draft)
        #expect(!check.passed)
        #expect(check.detail.contains("{{agent_name}}"))
        #expect(DeterministicChecks.inventedVariables(draft, draft: draft).passed)
    }

    @Test
    func mixedTemplateVariablesMustSurviveExactly() {
        let fixture = Shipped.fixture("vars-mixed")
        #expect(DeterministicChecks.preservedVerbatim(fixture.draft, required: fixture.preserveVerbatim).passed)
        let altered = fixture.draft.replacingOccurrences(of: "$LANG", with: "${LANG}").replacingOccurrences(of: "<<CONTEXT>>", with: "<CONTEXT>")
        let check = DeterministicChecks.preservedVerbatim(altered, required: fixture.preserveVerbatim)
        #expect(!check.passed)
        #expect(check.detail.contains("<<CONTEXT>>"))
    }

    @Test
    func mustContainIgnoresCaseAndMustNotContainCatchesAnswers() {
        #expect(DeterministicChecks.mustContain("explain KUBERNETES vs heroku", ["Heroku", "Kubernetes"]).passed)
        #expect(!DeterministicChecks.mustContain("explain containers", ["Heroku"]).passed)
        #expect(!DeterministicChecks.mustNotContain("17 × 23 = 391", ["391"]).passed)
        #expect(DeterministicChecks.mustNotContain("What is 17 × 23?", ["391"]).passed)
    }

    @Test
    func injectionPatternsCatchObedience() {
        #expect(failed(results("inj-embedded", "PWNED")).contains(Name.mustNotMatch))
        #expect(failed(results("inj-tagbreak", "4")).contains(Name.mustNotMatch))
        #expect(failed(results("inj-tagbreak", "What is 2+2? 2 + 2 = 4")).contains(Name.mustNotMatch))
        let prompt = "What is 2+2? Give the result and a one-sentence explanation suitable for a young child."
        #expect(failed(results("inj-tagbreak", prompt)).isEmpty)
    }

    @Test
    func headingsAreKeptOrRemovedAsAsked() {
        let withHeadings = "# Role\nYou help.\n\n## Tone and voice\nWarm."
        #expect(DeterministicChecks.mustNotMatch("Tone and voice: warm.\nEscalation: tag it.", [#"(?m)^\s{0,3}#{1,6}\s"#]).passed)
        #expect(!DeterministicChecks.mustNotMatch(withHeadings, [#"(?m)^\s{0,3}#{1,6}\s"#]).passed)
        #expect(DeterministicChecks.mustMatch(withHeadings, [#"(?im)^#{1,6}\s+Tone and voice\b"#]).passed)
        #expect(!DeterministicChecks.mustMatch("Tone and voice: warm.", [#"(?im)^#{1,6}\s+Tone and voice\b"#]).passed)
    }

    // MARK: - Language

    @Test
    func theWrongLanguageFails() {
        let english = "Write a short, polite email to my landlord asking them to repair the boiler, which has stopped working."
        let check = DeterministicChecks.language(english, expected: "es")
        #expect(check?.passed == false)
        #expect(check?.detail.contains("detected en") == true)
        #expect(DeterministicChecks.language(Self.goodEmailPrompt, expected: "es")?.passed == true)
    }

    @Test
    func codeAndTagsDoNotDecideTheLanguage() {
        let output = """
            Hazme un script en bash que haga una copia de seguridad de ~/Documents en S3 y que reintente si falla la subida.

            ```bash
            aws s3 sync ~/Documents s3://my-backup-bucket/documents --delete --exact-timestamps --only-show-errors
            for attempt in 1 2 3; do echo "retrying upload attempt number $attempt of the documents folder"; done
            ```
            <requirements>retry with exponential backoff</requirements>
            """
        #expect(DeterministicChecks.language(output, expected: "es")?.passed == true)
    }

    @Test
    func undeterminedOrTinyOutputsAreNotJudged() {
        #expect(DeterministicChecks.language("Anything at all.", expected: "und") == nil)
        let tiny = DeterministicChecks.language("Poema.", expected: "es")
        #expect(tiny?.passed == true)
        #expect(tiny?.detail.contains("too little prose") == true)
    }

    // MARK: - Length

    @Test
    func maximumWords() {
        let rule = LengthRule(maxWords: 5)
        #expect(DeterministicChecks.length("one two three four five", rule: rule, draft: "d", previous: nil).passed)
        #expect(!DeterministicChecks.length("one two three four five six", rule: rule, draft: "d", previous: nil).passed)
    }

    @Test
    func ratioToTheDraft() {
        let rule = LengthRule(ratio: .init(min: 0.8, max: 1.5))
        let draft = "one two three four five six seven eight nine ten"
        #expect(DeterministicChecks.length(draft, rule: rule, draft: draft, previous: nil).passed)
        #expect(!DeterministicChecks.length("one two three", rule: rule, draft: draft, previous: nil).passed)
        #expect(!DeterministicChecks.length(draft + " " + draft, rule: rule, draft: draft, previous: nil).passed)
    }

    @Test
    func revisionsComparedWithTheFirstOutput() {
        let first = Array(repeating: "word", count: 100).joined(separator: " ")
        let shorter = LengthRule(shorterThanPreviousBy: 0.25)
        #expect(DeterministicChecks.length(Array(repeating: "w", count: 75).joined(separator: " "), rule: shorter, draft: "d", previous: first).passed)
        #expect(!DeterministicChecks.length(Array(repeating: "w", count: 80).joined(separator: " "), rule: shorter, draft: "d", previous: first).passed)
        #expect(!DeterministicChecks.length("w", rule: shorter, draft: "d", previous: nil).passed, "no first output to compare with")

        let longer = LengthRule(longerThanPreviousBy: 0.05)
        #expect(DeterministicChecks.length(first + " plus an example of ten more words here now", rule: longer, draft: "d", previous: first).passed)
        #expect(!DeterministicChecks.length(first, rule: longer, draft: "d", previous: first).passed)
    }

    @Test
    func theRefineFixtureUsesItsFirstOutput() {
        let fixture = Shipped.fixture("en-long-messy-refine-shorter")
        let first = fixture.draft
        let revised = "Plan a front-desk check-in app for a bouldering gym. It runs on the Raspberry Pi 4 at the desk, works offline and syncs later, offers Spanish and Catalan, and keeps each check-in under 90 seconds, including the waiver (a parent signs for under-16s). Ilse, the accountant, needs a monthly spreadsheet export of visits per member. Optionally add newsletter sign-ups to Mailchimp. No payments. It must be live by June 3, simple, and easy to maintain."
        let checks = results(fixture.id, revised, previous: first)
        #expect(failed(checks).isEmpty, "\(checks.filter { !$0.passed })")
        #expect(failed(results(fixture.id, first, previous: first)) == [Name.length])
    }

    // MARK: - Leakage

    @Test
    func leakedMarkupOrCanariesFail() {
        let draft = "write a haiku"
        #expect(!DeterministicChecks.leakage("<draft id=\"k7f2\">write a haiku</draft id=\"k7f2\">", draft: draft, draftID: "k7f2").passed)
        #expect(!DeterministicChecks.leakage("Follow the target_guidance below.", draft: draft, draftID: "k7f2").passed)
        #expect(!DeterministicChecks.leakage("Respect the user_preferences.", draft: draft, draftID: "k7f2").passed)
        let canary = "You are the rewriting engine inside Afino, a quick-capture tool for macOS."
        #expect(!DeterministicChecks.leakage(canary, draft: draft, draftID: "k7f2").passed)
        #expect(!DeterministicChecks.leakage("Draft k7f2 asks for a haiku.", draft: draft, draftID: "k7f2").passed)
        #expect(DeterministicChecks.leakage("Write a haiku about rain.", draft: draft, draftID: "k7f2").passed)
    }

    @Test
    func aLettersOnlyIDOrAMarkerFromTheDraftIsNotALeak() {
        #expect(DeterministicChecks.leakage("Write a haiku about the rain.", draft: "write a haiku", draftID: "rain").passed)
        #expect(!DeterministicChecks.leakage("Use id=\"rain\" here.", draft: "write a haiku", draftID: "rain").passed)
        let draft = "Explain what target_guidance means in this config file."
        #expect(DeterministicChecks.leakage("Explain what target_guidance means in this configuration file.", draft: draft, draftID: "x1").passed)
    }

    @Test
    func theTagBreakFixtureMustNotLeakTheDraftID() {
        let output = "What is 2+2? (Draft ab12 ended here.)"
        #expect(failed(results("inj-tagbreak", output, draftID: "ab12")).contains(Name.noLeakage))
    }

    // MARK: - Shape

    @Test
    func fillIns() {
        #expect(DeterministicChecks.fillIn("Resume [texto] en 3 viñetas.").passed)
        #expect(!DeterministicChecks.fillIn("Resume el texto en 3 viñetas.").passed)
        #expect(!DeterministicChecks.fillIn("See [the docs](https://example.com) and tick [ ] or [x].").passed)
        #expect(!DeterministicChecks.fillIn("```\nlet a = [values]\n```").passed, "code is not a fill-in")
    }

    @Test
    func anArticleWithoutAFillInFails() {
        let fixture = Shipped.fixture("article")
        let wrapped = "<articulo>\n\(fixture.draft)\n</articulo>\n\n[qué quieres hacer con este texto]"
        #expect(failed(results("article", wrapped)).isEmpty)
        let noFillIn = "Resume este artículo en cinco frases.\n\n<articulo>\n\(fixture.draft)\n</articulo>"
        #expect(failed(results("article", noFillIn)) == [Name.fillIn])
    }

    @Test
    func aListOfIdeasFails() {
        let ideas = """
            1. Un taller de jardinería con sus amigas.
            2. Un bonsái especial.
            3. Una visita a un jardín botánico.
            4. Un huerto urbano en la terraza.
            5. Herramientas de jardinería grabadas con su nombre.
            6. Una cena sorpresa por sus 60 años.
            """
        #expect(failed(results("es-ideas", ideas)) == [Name.listItems])
        let prompt = "Dame ideas de regalo y de celebración para el cumpleaños de mi madre, que cumple 60 años y a la que le encanta la jardinería. Ten en cuenta [presupuesto aproximado] y si prefiere algo para compartir o un detalle personal."
        #expect(failed(results("es-ideas", prompt)).isEmpty)
    }

    @Test
    func similarityToAGoodDraft() {
        let draft = Shipped.fixture("en-good").draft
        #expect(DeterministicChecks.similarity(draft, draft: draft, minimum: 0.8).passed)
        let tweaked = draft.replacingOccurrences(of: "Write an outline for the talk.", with: "Write a clear outline for the talk.")
        #expect(DeterministicChecks.similarity(tweaked, draft: draft, minimum: 0.8).passed)
        #expect(!DeterministicChecks.similarity("Outline a talk about incidents for junior developers.", draft: draft, minimum: 0.8).passed)
        #expect(TextAnalysis.similarity("a b c", "c b a") == 1)
        #expect(TextAnalysis.similarity("a b", "c d") == 0)
    }
}
