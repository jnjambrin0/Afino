import Foundation

/// One forbidden pattern.
struct DesignLintRule: Sendable {
    let name: String
    /// An `NSRegularExpression` pattern matched per line.
    let pattern: String
    /// What to use instead, for whoever reads the rule.
    let hint: String
}

/// One match of a rule in a source file.
struct DesignLintViolation: Equatable, Sendable, CustomStringConvertible {
    /// Path relative to the scanned directory.
    let file: String
    let line: Int
    let rule: String
    let excerpt: String

    var description: String {
        "\(file):\(line) [\(rule)] \(excerpt)"
    }
}

/// A source scanner for the design rules: views draw with the Ember tokens
/// and kit, so literal fonts, radii, colours, spacing, shadows and gradients
/// may appear only in the token files. It scans any source folder: pass the
/// directory and the paths that are exempt (the token folder). Whole-line
/// `//` comments are skipped, so documentation may name a forbidden pattern.
enum DesignLint {
    /// The rules every Ember surface follows.
    static let kitRules: [DesignLintRule] = [
        DesignLintRule(name: "systemSizeFont", pattern: #"\.system\(size:"#, hint: "use EmberDesign.Typography"),
        DesignLintRule(name: "literalCornerRadius", pattern: #"cornerRadius: \d"#, hint: "use EmberDesign.Radius"),
        DesignLintRule(name: "rgbColor", pattern: #"Color\(red:"#, hint: "use system colors or EmberDesign.Brand"),
        DesignLintRule(
            name: "hardCodedGrey",
            pattern: #"Color\(white:|Color\.gray\b|NSColor\.(gray|lightGray|darkGray)\b"#,
            hint: "use hierarchical styles (.secondary, .fill.tertiary, .separator)"
        ),
        DesignLintRule(name: "swiftUIShadow", pattern: #"\.shadow\("#, hint: "no SwiftUI shadows on chrome (the window shadow is native)"),
        DesignLintRule(name: "gradient", pattern: #"(Linear|Radial|Angular|Elliptical)Gradient"#, hint: "no gradients"),
        DesignLintRule(
            name: "accentForeground",
            pattern: #"(foregroundStyle|foregroundColor)\([^)]*Brand\.accent\b"#,
            hint: "accent is never text; onAccent goes on accent, accentMark is for thin marks"
        ),
        DesignLintRule(name: "literalSpacing", pattern: #"spacing: [1-9]"#, hint: "use EmberDesign.Spacing"),
        DesignLintRule(name: "literalPadding", pattern: #"\.padding\((\.[a-zA-Z]+, )?[1-9]"#, hint: "use EmberDesign.Spacing"),
        DesignLintRule(name: "observableObject", pattern: #"\bObservableObject\b"#, hint: "use @Observable"),
        DesignLintRule(name: "published", pattern: #"@Published\b"#, hint: "use @Observable"),
    ]

    /// Every violation in the `.swift` files under `directory` (recursive).
    /// - Parameter exemptions: Paths relative to `directory` that are not
    ///   scanned: a folder (`"Tokens/"`) or a file (`"Theme.swift"`).
    static func violations(
        in directory: URL,
        rules: [DesignLintRule] = kitRules,
        exemptions: [String] = []
    ) throws -> [DesignLintViolation] {
        let root = directory.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let compiled = try rules.map { ($0, try NSRegularExpression(pattern: $0.pattern)) }
        var found: [DesignLintViolation] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(root) ? String(path.dropFirst(root.count)).trimmingPrefix("/") : Substring(path)
            if exemptions.contains(where: { isExempt(String(relative), by: $0) }) {
                continue
            }
            let source = try String(contentsOf: url, encoding: .utf8)
            found += violations(inSource: source, file: String(relative), compiled: compiled)
        }
        return found.sorted { ($0.file, $0.line, $0.rule) < ($1.file, $1.line, $1.rule) }
    }

    /// `Sources/<module>` of the package that contains `filePath`.
    static func sourcesDirectory(module: String, filePath: String = #filePath) -> URL {
        packageRoot(from: filePath).appending(path: "Sources/\(module)", directoryHint: .isDirectory)
    }

    /// The nearest ancestor of `filePath` with a `Package.swift`.
    static func packageRoot(from filePath: String = #filePath) -> URL {
        var directory = URL(filePath: filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appending(path: "Package.swift").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        return directory
    }

    private static func isExempt(_ relativePath: String, by exemption: String) -> Bool {
        if exemption.hasSuffix("/") {
            return relativePath.hasPrefix(exemption) || relativePath.contains("/\(exemption)")
        }
        return relativePath == exemption || relativePath.hasSuffix("/\(exemption)")
    }

    private static func violations(
        inSource source: String,
        file: String,
        compiled: [(DesignLintRule, NSRegularExpression)]
    ) -> [DesignLintViolation] {
        var found: [DesignLintViolation] = []
        for (index, line) in source.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            for (rule, regex) in compiled where regex.firstMatch(in: line, range: range) != nil {
                found.append(DesignLintViolation(file: file, line: index + 1, rule: rule.name, excerpt: trimmed))
            }
        }
        return found
    }
}
