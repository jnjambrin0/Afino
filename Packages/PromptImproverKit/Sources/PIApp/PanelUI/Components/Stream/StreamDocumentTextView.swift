import AppKit
import PIDesign

/// The result well's text view: TextKit 2, read-only, selectable, plain text out.
///
/// TextKit 2 must stay on: reading `layoutManager` would switch the view to TextKit 1 for good
/// (WWDC22 10090), so nothing in the stream components touches it.
final class StreamDocumentTextView: NSTextView {
    /// The context menu's Copy All title, from `Localizable.xcstrings`. Copy uses the Edit menu's
    /// title (`AppStrings.copy`).
    static var copyAllTitle: String {
        String(localized: "stream.copyAll", defaultValue: "Copy All", bundle: .module, comment: "Context menu item of the result: copies the whole prompt")
    }

    /// A text view set up for the well: read-only, no substitutions, checking or Writing Tools,
    /// no background, and the well's padding as its inset.
    static func make() -> StreamDocumentTextView {
        let textView = StreamDocumentTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.usesFindBar = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.writingToolsBehavior = .none
        textView.textContainerInset = NSSize(
            width: EmberDesign.Panel.wellHorizontalPadding,
            height: EmberDesign.Panel.wellVerticalPadding
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = StreamTextStyle.bodyFont
        textView.textColor = .labelColor
        textView.typingAttributes = StreamTextStyle.baseAttributes
        textView.focusRingType = .none
        return textView
    }

    // MARK: Plain-text copying

    /// Plain text only, so a drag or a service never carries the well's styling.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }

    /// Copies the selection as plain text (and nothing else).
    override func copy(_ sender: Any?) {
        writeSelectedText(to: .general)
    }

    /// Puts the whole text on the general pasteboard, as plain text.
    @objc func copyAll(_ sender: Any?) {
        writeAllText(to: .general)
    }

    /// The selected text (several selected ranges are joined by line breaks), or `nil`.
    var selectedPlainText: String? {
        let text = string as NSString
        let parts = selectedRanges.map(\.rangeValue).filter { $0.length > 0 && NSMaxRange($0) <= text.length }
        guard !parts.isEmpty else { return nil }
        return parts.map { text.substring(with: $0) }.joined(separator: "\n")
    }

    /// Writes the selection to `pasteboard` as plain text. Returns `false`, writing nothing, when
    /// nothing is selected.
    @discardableResult
    func writeSelectedText(to pasteboard: NSPasteboard) -> Bool {
        guard let text = selectedPlainText else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Writes the whole text to `pasteboard` as plain text.
    @discardableResult
    func writeAllText(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }

    // MARK: Context menu

    /// Copy and Copy All only: none of the text view's editing, font or speech items apply to a
    /// read-only prompt.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copy = NSMenuItem(title: AppStrings.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = selectedRange().length > 0
        let copyAll = NSMenuItem(title: Self.copyAllTitle, action: #selector(copyAll(_:)), keyEquivalent: "")
        copyAll.target = self
        copyAll.isEnabled = !string.isEmpty
        menu.addItem(copy)
        menu.addItem(copyAll)
        return menu
    }
}
