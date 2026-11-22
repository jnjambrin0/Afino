import Foundation
import Testing

/// The welcome draws only with design tokens: no literal fonts, radii, colours, spacing, padding,
/// durations, shadows or gradients, and no accent text, in `Sources/PIApp/Onboarding`.
/// `OnboardingLayout.swift` is the welcome's own token file; `WelcomeDebug.swift` is debug
/// tooling, compiled out of Release.
struct OnboardingDesignLintTests {
    private static let rules: [(name: String, pattern: String)] = [
        ("systemSizeFont", #"\.system\(size:"#),
        ("literalCornerRadius", #"cornerRadius: \d"#),
        ("rgbColor", #"Color\(red:|NSColor\(red:|NSColor\(srgbRed:"#),
        ("hardCodedGrey", #"Color\(white:|Color\.gray\b|NSColor\.(gray|lightGray|darkGray)\b"#),
        ("namedColor", #"Color\.(red|green|blue|orange|yellow|pink|purple|black|white)\b"#),
        ("swiftUIShadow", #"\.shadow\("#),
        ("gradient", #"(Linear|Radial|Angular|Elliptical)Gradient"#),
        ("accentForeground", #"(foregroundStyle|foregroundColor)\([^)]*Brand\.accent\b"#),
        ("literalSpacing", #"spacing: [1-9]"#),
        ("literalPadding", #"\.padding\((\.[a-zA-Z]+, )?[1-9]"#),
        ("literalFrame", #"\.frame\((width|height|minWidth|minHeight): [1-9]"#),
        ("literalAnimationDuration", #"(duration|Duration): [0-9]"#),
        ("literalSleep", #"\.(seconds|milliseconds)\([0-9]"#),
        ("observableObject", #"\bObservableObject\b|@Published\b"#),
        ("sharedSingleton", #"static (let|var) shared\b"#),
    ]

    private static let exemptions = ["OnboardingLayout.swift", "WelcomeDebug.swift"]

    @Test func welcomeSourcesUseOnlyTokens() throws {
        var root = URL(filePath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appending(path: "Package.swift").path), root.path != "/" {
            root = root.deletingLastPathComponent()
        }
        let folder = root.appending(path: "Sources/PIApp/Onboarding")
        let compiled = try Self.rules.map { ($0.name, try NSRegularExpression(pattern: $0.pattern)) }
        let files = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var violations: [String] = []
        var scanned = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let relative = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
            if Self.exemptions.contains(where: { relative.hasSuffix($0) }) { continue }
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                let range = NSRange(line.startIndex..., in: line)
                for (name, regex) in compiled where regex.firstMatch(in: line, range: range) != nil {
                    violations.append("\(relative):\(index + 1) [\(name)] \(trimmed)")
                }
            }
        }
        #expect(scanned > 10)
        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }
}
