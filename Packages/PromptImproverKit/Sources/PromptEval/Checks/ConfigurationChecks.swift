import Foundation
import PIPrompts
import PIProviders

/// Assertions made once per configuration: is the stable prefix big enough to cache, and does a
/// second request with the same prefix actually read from the cache?
enum ConfigurationChecks {
    /// Check names as `configuration-checks.json` and the summary show them.
    enum Name {
        static let prefixMinimum = "cache_prefix_minimum"
        static let cacheRead = "cache_read"
    }

    /// The smallest prompt prefix each provider caches, in tokens.
    static func minimumCacheableTokens(for provider: ProviderID) -> Int {
        switch provider {
        case .anthropic: 512
        case .openai: 1_024
        }
    }

    /// The system prefix sizes for every target and preference set the fixtures use, estimated
    /// as characters ÷ 4; passes when the smallest reaches the provider's minimum.
    static func prefixMinimum(
        configuration: EvalConfiguration,
        fixtures: [Fixture],
        library: TargetPackLibrary,
        composer: PromptComposer
    ) -> ConfigurationCheck {
        var smallest: (characters: Int, target: String)?
        var seen = Set<String>()
        for fixture in fixtures {
            guard let target = library.pack(withID: fixture.target) else { continue }
            let blocks = composer.systemBlocks(for: target, preferences: fixture.promptPreferences)
            let key = blocks.joined(separator: "\u{1F}")
            guard seen.insert(key).inserted else { continue }
            // OpenAI joins the blocks with a blank line; Anthropic sends them as separate blocks.
            let characters = blocks.joined(separator: "\n\n").count
            if smallest == nil || characters < smallest!.characters {
                smallest = (characters, target.id)
            }
        }
        let minimum = minimumCacheableTokens(for: configuration.provider)
        guard let smallest else {
            return ConfigurationCheck(configurationID: configuration.id, name: Name.prefixMinimum, status: .warning,
                                      detail: "no fixture with a known target to measure")
        }
        let tokens = CostEstimator.estimatedTokens(characters: smallest.characters)
        let detail = "smallest system prefix ≈ \(tokens) tokens (\(smallest.characters) characters ÷ 4, target \(smallest.target)); \(configuration.provider.displayName) caches from \(minimum)"
        return ConfigurationCheck(configurationID: configuration.id, name: Name.prefixMinimum,
                                  status: tokens >= minimum ? .pass : .fail, detail: detail)
    }

    /// Judges the second of two identical requests: cached input tokens must be reported and
    /// above zero. A failed probe or missing usage is a warning, not a failure.
    static func cacheRead(configurationID: String, first: TurnMeasurement, second: TurnMeasurement) -> ConfigurationCheck {
        func check(_ status: ConfigurationCheck.Status, _ detail: String) -> ConfigurationCheck {
            ConfigurationCheck(configurationID: configurationID, name: Name.cacheRead, status: status, detail: detail)
        }
        if let failure = first.failureDescription ?? second.failureDescription {
            return check(.warning, "cache probe did not complete: \(failure)")
        }
        guard let usage = second.usage else {
            return check(.warning, "the provider reported no usage, so cache reads cannot be confirmed")
        }
        guard let cached = usage.cacheReadInputTokens else {
            return check(.warning, "the provider reported usage without cached input tokens")
        }
        let written = first.usage?.cacheCreationInputTokens.map { ", first request wrote \($0)" } ?? ""
        return cached > 0
            ? check(.pass, "second identical-prefix request read \(cached) cached input tokens\(written)")
            : check(.fail, "second identical-prefix request read 0 cached input tokens\(written)")
    }
}
