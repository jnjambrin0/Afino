import Foundation
import Testing

/// The panel draws only with design tokens: no literal fonts, radii, colours, spacing, padding,
/// shadows or gradients, and no accent text, in `Sources/PIApp/Panel` and `Sources/PIApp/PanelUI`.
/// `PanelLayout.swift` is the panel's own token file; the stream view, the height animator and
/// the debug demo are not panel views.
struct PanelDesignLintTests {
    private static let rules: [(name: String, pattern: String)] = [
        ("systemSizeFont", #"\.system\(size:"#),
        ("literalCornerRadius", #"cornerRadius: \d"#),
        ("rgbColor", #"Color\(red:"#),
        ("hardCodedGrey", #"Color\(white:|Color\.gray\b|NSColor\.(gray|lightGray|darkGray)\b"#),
        ("swiftUIShadow", #"\.shadow\("#),
        ("gradient", #"(Linear|Radial|Angular|Elliptical)Gradient"#),
        ("accentForeground", #"(foregroundStyle|foregroundColor)\([^)]*Brand\.accent\b"#),
        ("literalSpacing", #"spacing: [1-9]"#),
        ("literalPadding", #"\.padding\((\.[a-zA-Z]+, )?[1-9]"#),
        ("literalAnimationDuration", #"(duration|Duration): [0-9]"#),
        ("observableObject", #"\bObservableObject\b|@Published\b"#),
        ("sharedSingleton", #"static (let|var) shared\b"#),
    ]

    private static let exemptions = ["PanelUI/PanelLayout.swift", "PanelUI/Components/", "PanelUI/Demo/"]

    @Test func panelSourcesUseOnlyTokens() throws {
        var root = URL(filePath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appending(path: "Package.swift").path), root.path != "/" {
            root = root.deletingLastPathComponent()
        }
        let app = root.appending(path: "Sources/PIApp")
        let compiled = try Self.rules.map { ($0.name, try NSRegularExpression(pattern: $0.pattern)) }
        var violations: [String] = []
        var scanned = 0
        for folder in ["Panel", "PanelUI"] {
            let directory = app.appending(path: folder)
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in files where url.pathExtension == "swift" {
                let relative = String(url.standardizedFileURL.path.dropFirst(app.standardizedFileURL.path.count + 1))
                if Self.exemptions.contains(where: { relative.hasPrefix($0) }) { continue }
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
        }
        #expect(scanned > 20)
        #expect(violations.isEmpty, "\(violations.joined(separator: "\n"))")
    }
}
