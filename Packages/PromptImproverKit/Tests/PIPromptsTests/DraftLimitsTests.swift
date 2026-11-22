import Testing
@testable import PIPrompts

struct DraftLimitsTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let label: String
        let draft: String
        let status: DraftValidation.Status

        var testDescription: String { label }
    }

    static let cases: [Case] = [
        Case(label: "empty", draft: "", status: .empty),
        Case(label: "whitespace only", draft: "  \n\t \r\n  ", status: .empty),
        Case(label: "one character", draft: "a", status: .acceptable),
        Case(label: "8,000", draft: String(repeating: "a", count: 8_000), status: .acceptable),
        Case(label: "8,001", draft: String(repeating: "a", count: 8_001), status: .long),
        Case(label: "30,000", draft: String(repeating: "a", count: 30_000), status: .long),
        Case(label: "30,001", draft: String(repeating: "a", count: 30_001), status: .tooLong),
        Case(label: "8,001 emoji count as characters", draft: String(repeating: "👍🏽", count: 8_001), status: .long),
        Case(label: "30,000 including CRLF pairs", draft: String(repeating: "a\r\n", count: 15_000), status: .long),
    ]

    @Test(arguments: cases)
    func boundaries(_ testCase: Case) {
        let validation = DraftLimits.validate(testCase.draft)

        #expect(validation.status == testCase.status)
        #expect(validation.characterCount == testCase.draft.count)
        #expect(validation.isSubmittable == [.acceptable, .long].contains(testCase.status))
        #expect(validation.showsLengthWarning == (testCase.status == .long))
    }

    @Test func limitsAreEightAndThirtyThousandCharacters() {
        #expect(DraftLimits.softLimit == 8_000)
        #expect(DraftLimits.hardLimit == 30_000)
    }
}
