import Foundation
import PIProviders

/// Every string the panel shows or speaks, in English and Spanish (`Resources/Panel.xcstrings`).
///
/// Keys are looked up only through `t(_:)` and `f(_:_:)` in this file, so the catalog test can
/// read every key the panel uses from this one source file.
enum PanelStrings {
    static let table = "Panel"
    static var bundle: Bundle { .module }

    /// The string for `key` in the user's language.
    private static func t(_ key: StaticString) -> String {
        // A `String` value, not a literal: a literal would be read as an interpolation.
        let name = key.description
        return String(localized: String.LocalizationValue(name), table: table, bundle: bundle)
    }

    /// The string for `key` with its format specifiers filled in, in the user's locale.
    private static func f(_ key: StaticString, _ arguments: any CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: arguments)
    }

    // MARK: Compose

    static var composePlaceholder: String { t("compose.placeholder") }
    static var longDraft: String { t("compose.longDraft") }
    static var tooLong: String { t("error.tooLong") }

    // MARK: Target

    static var targetPrefix: String { t("target.prefix") }
    static var anyModel: String { t("target.any") }
    static var targetMenuTitle: String { t("target.menuTitle") }
    static func targetAccessibility(_ name: String) -> String { f("target.accessibility", name) }
    static var targetAccessibilityHint: String { t("target.accessibilityHint") }

    // MARK: Actions

    static var improve: String { t("action.improve") }
    static var stop: String { t("action.stop") }
    static var refine: String { t("action.refine") }
    static var copyAndClose: String { t("action.copyClose") }
    static func rewriteFor(_ name: String) -> String { f("action.rewriteFor", name) }
    static var tryAgain: String { t("action.tryAgain") }
    static var regenerate: String { t("action.regenerate") }
    static var editOriginal: String { t("action.editOriginal") }
    static var edit: String { t("action.edit") }
    static var newPrompt: String { t("action.newPrompt") }
    static var openSettings: String { t("action.openSettings") }
    static var copy: String { t("action.copy") }
    static var showOriginal: String { t("action.showOriginal") }
    static var hideOriginal: String { t("action.hideOriginal") }
    static var history: String { t("action.history") }
    static var settings: String { t("action.settings") }
    static var copyDetails: String { t("action.copyDetails") }
    static var actions: String { t("action.actions") }
    static var jumpToEnd: String { t("action.jumpToEnd") }
    static var undo: String { t("action.undo") }
    static var customInstructions: String { t("action.customInstructions") }
    static func customInstructionsState(enabled: Bool) -> String {
        enabled ? t("state.on") : t("state.off")
    }

    // MARK: Hints

    static var newLine: String { t("hint.newLine") }
    static var open: String { t("hint.open") }
    static var delete: String { t("hint.delete") }
    static var back: String { t("hint.back") }

    // MARK: Menus

    static func menuEngine(_ provider: String) -> String { f("menu.engine", provider) }

    static var presetQuality: String { t("preset.quality") }
    static var presetBalanced: String { t("preset.balanced") }
    static var presetFast: String { t("preset.fast") }

    static var refineShorter: String { t("preset.shorter") }
    static var refineDetailed: String { t("preset.detailed") }
    static var refineExamples: String { t("preset.examples") }

    // MARK: Status

    static var thinking: String { t("status.thinking") }
    static func thinking(seconds: Int) -> String { f("status.thinkingElapsed", seconds) }
    static var writing: String { t("status.writing") }
    static var copied: String { t("status.copied") }
    static var stopped: String { t("status.stopped") }
    static func writtenBy(_ model: String) -> String { f("status.writtenBy", model) }

    static func retrying(_ reason: RetryReason) -> String {
        switch reason {
        case .rateLimited: t("status.retrying.rateLimited")
        case .overloaded: t("status.retrying.overloaded")
        case .serverError: t("status.retrying.serverError")
        case .timedOut: t("status.retrying.timedOut")
        case .network: t("status.retrying.network")
        case .requestedByServer: t("status.retrying.other")
        }
    }

    // MARK: Result

    static var refinePlaceholder: String { t("refine.placeholder") }
    static var resultAccessibilityLabel: String { t("ax.result") }
    static var originalAccessibilityLabel: String { t("ax.original") }
    static func versionStepper(_ index: Int, of count: Int) -> String { f("version.stepper", index, count) }
    static func versionAccessibility(_ index: Int, of count: Int) -> String { f("version.accessibility", index, count) }
    static var previousVersion: String { t("version.previous") }
    static var nextVersion: String { t("version.next") }
    static var stoppedNotice: String { t("notice.stopped") }

    // MARK: Errors

    static func invalidKey(_ provider: String) -> String { f("error.invalidKey", provider) }
    static func noKey(_ provider: String) -> String { f("error.noKey", provider) }
    static func noCredit(_ provider: String) -> String { f("error.noCredit", provider) }
    static func modelUnavailable(_ model: String) -> String { f("error.modelUnavailable", model) }
    static func rateLimited(seconds: Int) -> String { f("error.rateLimited", seconds) }
    static var rateLimitedNow: String { t("error.rateLimitedNow") }
    static func overloaded(_ provider: String) -> String { f("error.overloaded", provider) }
    static func serverError(_ provider: String) -> String { f("error.serverError", provider) }
    static var offline: String { t("error.offline") }
    static func timeout(seconds: Int) -> String { f("error.timeout", seconds) }
    static var dropped: String { t("error.dropped") }
    static var droppedEarly: String { t("error.droppedEarly") }
    static var secureConnection: String { t("error.secureConnection") }
    static var refusal: String { t("error.refusal") }
    static var truncated: String { t("error.truncated") }
    static var truncatedEmpty: String { t("error.truncatedEmpty") }
    static var emptyOutput: String { t("error.emptyOutput") }
    static func malformed(_ provider: String) -> String { f("error.malformed", provider) }
    static func invalidRequest(_ provider: String) -> String { f("error.invalidRequest", provider) }
    static func permissionDenied(_ provider: String) -> String { f("error.permissionDenied", provider) }
    static var contextTooLong: String { t("error.contextTooLong") }
    static var genericError: String { t("error.generic") }
    /// When the provider is not known, messages name "the provider".
    static var theProvider: String { t("error.theProvider") }

    // MARK: Copy details

    static func detailsProvider(_ value: String) -> String { f("details.provider", value) }
    static func detailsModel(_ value: String) -> String { f("details.model", value) }
    static func detailsRequest(_ value: String) -> String { f("details.request", value) }
    static func detailsError(_ value: String) -> String { f("details.error", value) }
    static var detailsNone: String { t("details.none") }

    // MARK: Setup

    static var setupTitle: String { t("setup.title") }
    static var setupBody: String { t("setup.body") }
    static func keyPlaceholder(_ provider: String) -> String { f("setup.keyPlaceholder", provider) }
    static var keyFieldLabel: String { t("setup.keyFieldLabel") }
    static var providerLabel: String { t("setup.providerLabel") }
    static var paste: String { t("setup.paste") }
    static var getKey: String { t("setup.getKey") }
    static var saveKey: String { t("setup.save") }
    static func keyPrivacy(_ provider: String) -> String { f("key.privacy", provider) }
    static var checking: String { t("setup.checking") }
    static var keyWorks: String { t("setup.works") }
    static var keyRejected: String { t("setup.rejected") }
    static func wrongProvider(_ provider: String) -> String { f("setup.wrongProvider", provider) }
    static func useProvider(_ provider: String) -> String { f("setup.useProvider", provider) }
    static var keyUnverified: String { t("setup.unverified") }
    static var keyStoreFailed: String { t("setup.storeFailed") }
    static var keyEmpty: String { t("setup.empty") }

    // MARK: History

    static var historyFilterPlaceholder: String { t("history.filterPlaceholder") }
    static var historyEmpty: String { t("history.empty") }
    static var historyNoMatches: String { t("history.noMatches") }
    static var historyDeleted: String { t("history.deleted") }
    static var historyNow: String { t("history.now") }
    static func historyCount(_ count: Int) -> String {
        String(localized: "history.count \(count)", table: table, bundle: bundle)
    }

    // MARK: Accessibility announcements

    static func improvingFor(_ target: String) -> String { f("ax.improvingFor", target) }
    static func done(words: Int) -> String { f("ax.done", words) }

    // MARK: Settings › Shortcuts

    static var groupWrite: String { t("shortcuts.write") }
    static var groupResult: String { t("shortcuts.result") }
    static var groupNavigate: String { t("shortcuts.navigate") }
    static var nextTarget: String { t("shortcuts.nextTarget") }
    static var previousTarget: String { t("shortcuts.previousTarget") }
    static var chooseTarget: String { t("shortcuts.chooseTarget") }
    static var previousDraft: String { t("shortcuts.previousDraft") }
    static var resultReturn: String { t("shortcuts.resultReturn") }
    static var stopRun: String { t("shortcuts.stop") }
    static var closePanel: String { t("shortcuts.close") }
}
