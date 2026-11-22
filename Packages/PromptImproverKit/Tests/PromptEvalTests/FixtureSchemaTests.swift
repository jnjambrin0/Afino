import Foundation
import PIPrompts
import Testing
@testable import PromptEval

/// The shipped fixtures decode and make sense, so a live run never fails on a broken fixture.
struct FixtureSchemaTests {
    let fixtures = Shipped.fixtures.fixtures

    @Test
    func everyFixtureDecodesWithAUniqueID() throws {
        let library = try FixtureLibrary.bundled()
        #expect(library.fixtures.count == 31, "27 base fixtures (number 26 comes in two forms) plus 4 variants")
        let ids = library.fixtures.map(\.id)
        #expect(Set(ids).count == ids.count)
        for fixture in library.fixtures {
            #expect(!fixture.title.isEmpty, "\(fixture.id) has no title")
            #expect(!fixture.draft.isEmpty, "\(fixture.id) has no draft")
        }
    }

    @Test
    func everyTargetIsAShippedPackAndEveryPackIsUsed() {
        let packIDs = Set(Shipped.packs.packs.map(\.id))
        for fixture in fixtures {
            #expect(packIDs.contains(fixture.target), "\(fixture.id) targets unknown pack \(fixture.target)")
        }
        #expect(Set(fixtures.map(\.target)) == packIDs)
        #expect(Set(Shipped.fixtures.smoke.map(\.target)) == packIDs, "smoke exercises every pack")
    }

    @Test
    func eightFixturesAreInSmoke() {
        #expect(Shipped.fixtures.smoke.count == 8)
    }

    @Test
    func everyDraftCanBeSubmitted() {
        for fixture in fixtures {
            #expect(DraftLimits.validate(fixture.draft).isSubmittable, "\(fixture.id)")
        }
    }

    @Test
    func preservedStringsReallyOccurInTheDraft() {
        for fixture in fixtures {
            for text in fixture.preserveVerbatim {
                #expect(fixture.draft.contains(text), "\(fixture.id): \"\(text.prefix(40))\" is not in the draft")
            }
        }
    }

    @Test
    func canariesReallyOccurInCoreText() {
        let core = Shipped.composer.core
        #expect(LeakMarkers.canaries.count == 3)
        for canary in LeakMarkers.canaries {
            #expect(core.contains(canary), "\"\(canary)\" is not in core.txt")
        }
        for fixture in fixtures {
            for canary in LeakMarkers.canaries {
                #expect(!fixture.draft.localizedCaseInsensitiveContains(canary), "\(fixture.id) would exempt a canary")
            }
        }
    }

    @Test
    func everyPatternCompiles() {
        for fixture in fixtures {
            for pattern in fixture.mustMatch + fixture.mustNotMatch {
                #expect((try? NSRegularExpression(pattern: pattern)) != nil, "\(fixture.id): \(pattern)")
            }
        }
    }

    @Test
    func languagesAndLengthRulesAreWellFormed() {
        for fixture in fixtures {
            #expect(["en", "es", "und"].contains(fixture.expectedLanguage), "\(fixture.id)")
            guard let rule = fixture.length else { continue }
            #expect(!rule.isEmpty, "\(fixture.id) has an empty length rule")
            #expect(!rule.isRelativeToPrevious || fixture.refine != nil, "\(fixture.id): a relative rule needs a refinement")
            if let ratio = rule.ratio, let low = ratio.min, let high = ratio.max {
                #expect(low < high, "\(fixture.id)")
            }
        }
        for fixture in fixtures where fixture.refine != nil {
            #expect(fixture.length?.isRelativeToPrevious == true, "\(fixture.id): a refinement says how its revision relates to the first output")
        }
    }

    @Test
    func requiredFactsComeFromTheDraft() {
        // Without a language preference, everything a fixture requires is already in the draft.
        for fixture in fixtures where fixture.preferences?.language == nil {
            for text in fixture.mustContain {
                #expect(fixture.draft.localizedCaseInsensitiveContains(text), "\(fixture.id): \"\(text)\" is not in the draft")
            }
        }
    }

    @Test
    func variantsResolveToTheirBase() throws {
        let variants = fixtures.filter { $0.variantOf != nil }
        #expect(variants.count == 4)
        for variant in variants {
            let base = try #require(Shipped.fixtures.fixture(withID: variant.variantOf ?? ""))
            #expect(variant.draft == base.draft)
            #expect(variant.target == base.target)
        }
        #expect(Shipped.fixture("en-long-messy-refine-shorter").length?.shorterThanPreviousBy == 0.25)
        #expect(Shipped.fixture("es-email-english").preferences?.language == .english)
        #expect(Shipped.fixture("en-system-no-headings").preferences?.customInstructions == "No Markdown headings.")
    }

    @Test
    func longFixturesHaveTheirIntendedSize() {
        func words(_ id: String) -> Int { TextAnalysis.wordCount(Shipped.fixture(id).draft) }
        #expect((400...500).contains(words("en-long-messy")))
        #expect((650...750).contains(words("en-system")))
        #expect((160...200).contains(words("en-good")))
        #expect((320...380).contains(words("article")))
        let snippetLines = Shipped.fixture("en-code-snippet").preserveVerbatim[0].split(separator: "\n", omittingEmptySubsequences: false).count
        #expect((22...30).contains(snippetLines))

        let meta = Shipped.fixture("meta-note")
        let note = "mejora este prompt y que quede más corto: "
        #expect(meta.draft.hasPrefix(note))
        let embeddedWords = TextAnalysis.wordCount(String(meta.draft.dropFirst(note.count)))
        #expect((110...135).contains(embeddedWords))
        #expect(meta.length?.maxWords == embeddedWords - 1, "shorter than the embedded prompt")
    }

    @Test
    func theUnchangedDraftPassesTheFidelityChecks() {
        // Echoing the draft keeps everything, so the fidelity checks must accept it.
        for fixture in fixtures {
            let input = CheckInput(fixture: fixture, output: fixture.draft, draftID: "zz99")
            #expect(DeterministicChecks.preservedVerbatim(fixture.draft, required: fixture.preserveVerbatim).passed, "\(fixture.id)")
            #expect(DeterministicChecks.inventedVariables(input.output, draft: fixture.draft).passed, "\(fixture.id)")
            #expect(DeterministicChecks.leakage(input.output, draft: fixture.draft, draftID: input.draftID).passed, "\(fixture.id)")
        }
    }
}
