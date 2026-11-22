import Foundation
import Testing

/// The package's architecture rules, checked against the source of every module so they cannot
/// erode quietly: `@Observable` instead of `ObservableObject`, dependencies passed by initializer
/// instead of shared singletons, logging through `Log.logger`, a few system APIs reachable from
/// one file only, no interface frameworks below the interface, and module imports that only point
/// down the layers described in `Package.swift`. Comments are skipped, so they may name what is
/// forbidden.
struct ArchitectureLintTests {
    private static let sourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // PIAppTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // PromptImproverKit
        .appending(path: "Sources", directoryHint: .isDirectory)

    private struct Rule {
        let name: String
        let pattern: String
        /// Path fragments (relative to Sources) where the pattern is expected.
        var allowedIn: [String] = []
    }

    private static let rules: [Rule] = [
        Rule(name: "Use @Observable, not ObservableObject", pattern: #"\bObservableObject\b|@Published\b|@StateObject\b|@ObservedObject\b"#),
        Rule(name: "No shared singletons: pass dependencies by initializer", pattern: #"static\s+(let|var)\s+shared\b"#),
        Rule(name: "Inject the URLSession (ProviderSession.make())", pattern: #"URLSession\.shared"#),
        Rule(name: "Log with Log.logger, never print", pattern: #"^\s*(debugPrint|print)\("#, allowedIn: ["PromptEval/"]),
        Rule(name: "Activate the app only through the AppActivating seam",
             pattern: #"activate\(ignoringOtherApps"#, allowedIn: ["PIApp/Panel/AppActivator.swift"]),
        Rule(name: "The Keychain is only touched by KeychainSecretStore",
             pattern: #"\bSecItem(Add|Update|CopyMatching|Delete)\b"#, allowedIn: ["PIFoundation/Secrets/KeychainSecretStore.swift"]),
        Rule(name: "UserDefaults goes through ConfigStore",
             pattern: #"UserDefaults\.standard"#,
             allowedIn: ["PIFoundation/Config/", "PICore/Legacy/LegacyCleanup.swift", "PIApp/Updates/"]),
    ]

    /// Modules below the interface must not know about windows or views.
    private static let headlessModules = ["PIFoundation", "PIProviders", "PIPrompts", "PromptEval"]

    private struct Line {
        let file: String
        let number: Int
        let text: String
    }

    private static func sourceLines() throws -> [Line] {
        let root = sourcesDirectory.path(percentEncoded: false)
        guard let files = FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var lines: [Line] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let relative = String(url.path(percentEncoded: false).dropFirst(root.count))
            let contents = try String(contentsOf: url, encoding: .utf8)
            for (index, text) in contents.components(separatedBy: "\n").enumerated() {
                // Comments may name what is forbidden.
                guard !text.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                lines.append(Line(file: relative, number: index + 1, text: text))
            }
        }
        return lines
    }

    @Test
    func sourcesFollowTheArchitectureRules() throws {
        let lines = try Self.sourceLines()
        #expect(lines.count > 1_000, "The sources were found")
        for rule in Self.rules {
            let regex = try NSRegularExpression(pattern: rule.pattern)
            let offenders = lines.filter { line in
                guard !rule.allowedIn.contains(where: { line.file.contains($0) }) else { return false }
                return regex.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) != nil
            }
            let report = offenders.prefix(10).map { "\($0.file):\($0.number): \($0.text.trimmingCharacters(in: .whitespaces))" }
            #expect(offenders.isEmpty, "\(rule.name)\n\(report.joined(separator: "\n"))")
        }
    }

    @Test
    func headlessModulesDoNotImportInterfaceFrameworks() throws {
        let regex = try NSRegularExpression(pattern: #"^\s*(@preconcurrency\s+)?import\s+(AppKit|SwiftUI)\b"#)
        let offenders = try Self.sourceLines().filter { line in
            guard Self.headlessModules.contains(where: { line.file.hasPrefix($0 + "/") }) else { return false }
            return regex.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) != nil
        }
        #expect(offenders.isEmpty, "\(offenders.map { "\($0.file):\($0.number)" })")
    }

    @Test
    func layersOnlyDependDownwards() throws {
        // module → modules of the package it may import
        let allowed: [String: Set<String>] = [
            "PIFoundation": [],
            "PIProviders": ["PIFoundation"],
            "PIPrompts": ["PIFoundation"],
            "PIDesign": [],
            "PICore": ["PIFoundation", "PIProviders", "PIPrompts"],
            "PromptEval": ["PIFoundation", "PIProviders", "PIPrompts"],
            "PIApp": ["PIFoundation", "PIProviders", "PIPrompts", "PIDesign", "PICore"],
        ]
        let regex = try NSRegularExpression(pattern: #"^\s*(@testable\s+)?import\s+(PI[A-Za-z]+|PromptEval)\b"#)
        var offenders: [String] = []
        for line in try Self.sourceLines() {
            guard let module = line.file.split(separator: "/").first.map(String.init), let permitted = allowed[module],
                  let match = regex.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)),
                  let range = Range(match.range(at: 2), in: line.text) else { continue }
            let imported = String(line.text[range])
            if imported != module, !permitted.contains(imported) {
                offenders.append("\(line.file):\(line.number) imports \(imported)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
