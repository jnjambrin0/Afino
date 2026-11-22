import Foundation
import Testing

/// The kit draws only with its tokens: no literal fonts, radii, colours,
/// spacing, shadows or gradients outside `Sources/PIDesign/Tokens/`, and no
/// `ObservableObject` anywhere.
struct DesignSystemLintTests {
    static let tokenFolder = "Tokens/"

    @Test
    func kitSourcesFollowTheDesignRules() throws {
        let sources = DesignLint.sourcesDirectory(module: "PIDesign")
        #expect(FileManager.default.fileExists(atPath: sources.appending(path: "Tokens/EmberDesign.swift").path))

        let violations = try DesignLint.violations(in: sources, exemptions: [Self.tokenFolder])
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test
    func noKitSourceUsesObservableObject() throws {
        let sources = DesignLint.sourcesDirectory(module: "PIDesign")
        let rules = DesignLint.kitRules.filter { ["observableObject", "published"].contains($0.name) }
        let violations = try DesignLint.violations(in: sources, rules: rules)
        #expect(violations.isEmpty, "\(violations.map(\.description).joined(separator: "\n"))")
    }

    @Test
    func scannerFindsEveryRuleAndHonorsExemptions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DesignLint-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory.appending(path: "Tokens"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let offending = """
        Text("a").font(.system(size: 13))
        RoundedRectangle(cornerRadius: 8)
        Color(red: 1, green: 0, blue: 0)
        Color(white: 0.5)
        view.shadow(radius: 2)
        LinearGradient(colors: [], startPoint: .top, endPoint: .bottom)
        Text("x").foregroundStyle(EmberDesign.Brand.accent)
        HStack(spacing: 6) {}
        view.padding(.horizontal, 12)
        final class Model: ObservableObject {}
        @Published var value = 0
        // A comment may mention .shadow( and cornerRadius: 4.
        Text("ok").foregroundStyle(EmberDesign.Brand.accentMark).padding(EmberDesign.Spacing.s)
        """
        try offending.write(to: directory.appending(path: "View.swift"), atomically: true, encoding: .utf8)
        try offending.write(to: directory.appending(path: "Tokens/Theme.swift"), atomically: true, encoding: .utf8)

        let violations = try DesignLint.violations(in: directory, exemptions: ["Tokens/"])
        #expect(Set(violations.map(\.rule)) == Set(DesignLint.kitRules.map(\.name)))
        #expect(violations.allSatisfy { $0.file == "View.swift" })
        #expect(violations.count == DesignLint.kitRules.count)
        #expect(violations.first { $0.rule == "systemSizeFont" }?.line == 1)

        let fileExempt = try DesignLint.violations(in: directory, exemptions: ["View.swift", "Tokens/"])
        #expect(fileExempt.isEmpty)
    }
}
