import Foundation
import Testing

/// The package manifest and the Xcode project each state a deployment target. They must agree,
/// and the project must state it once, so the app and its package never build for different
/// minimum systems.
struct DeploymentTargetTests {
    @Test
    func packageAndProjectDeclareTheSameDeploymentTarget() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PIFoundationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // PromptImproverKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repository root
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Packages/PromptImproverKit/Package.swift"), encoding: .utf8)
        let project = try String(
            contentsOf: root.appendingPathComponent("PromptImprover.xcodeproj/project.xcproj"), encoding: .utf8)

        let packageTarget = try #require(firstMatch(#"\.macOS\("([0-9.]+)"\)"#, in: manifest))
        let projectTarget = try #require(firstMatch(#""MACOSX_DEPLOYMENT_TARGET": "([0-9.]+)""#, in: project))
        #expect(packageTarget == projectTarget)
        #expect(project.components(separatedBy: "MACOSX_DEPLOYMENT_TARGET").count == 2,
                "The deployment target is set once, at project level")
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
