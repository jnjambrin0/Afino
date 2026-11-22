import AppKit
import Carbon.HIToolbox
import PIDesign

/// What Return does in the compose input.
nonisolated enum ComposeReturnAction: Equatable, Sendable {
    /// Hand the draft over (Return, ⌘Return).
    case submit
    /// Start a new line (⇧Return, ⌥Return).
    case newline
    /// Leave the key to the text system: an input method is composing (Return confirms the
    /// composition and never submits), or the key is not Return at all.
    case passThrough

    static func action(keyCode: Int, modifiers: NSEvent.ModifierFlags, hasMarkedText: Bool) -> ComposeReturnAction {
        guard keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter, !hasMarkedText else {
            return .passThrough
        }
        switch modifiers.intersection([.command, .option, .control, .shift]) {
        case [], .command: return .submit
        case .shift, .option: return .newline
        default: return .passThrough
        }
    }
}

/// The compose input's text view: TextKit 2, plain text only.
///
/// TextKit 2 must stay on: reading `layoutManager` would switch the view to TextKit 1 for good
/// (WWDC22 10090) and limit Writing Tools to its panel (WWDC24 10168), so nothing touches it.
final class ComposeTextView: NSTextView {
    /// Return (or ⌘Return) outside an input method's composition.
    var onSubmit: (() -> Void)?
    /// The text changed, including an input method's marked text: the owner measures it.
    var onTextChange: (() -> Void)?

    static func make(font: NSFont) -> ComposeTextView {
        let textView = ComposeTextView(usingTextLayoutManager: true)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        // Prompts are often code or structured text: never rewrite quotes, dashes or text the
        // user typed, and no red underlines in a quick-capture field.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.writingToolsBehavior = .default
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = font
        textView.textColor = .labelColor
        // The accent caret is the app's signature; selection keeps the system's accent.
        textView.insertionPointColor = EmberDesign.Brand.nsAccentMark
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        return textView
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        switch ComposeReturnAction.action(
            keyCode: Int(event.keyCode),
            modifiers: event.modifierFlags,
            hasMarkedText: hasMarkedText()
        ) {
        case .submit:
            onSubmit?()
        case .newline:
            insertNewlineIgnoringFieldEditor(nil)
        case .passThrough:
            super.keyDown(with: event)
        }
    }

    // MARK: Plain text only

    /// Inserts the clipboard's text as typed text. Done by hand: with the readable types narrowed
    /// to plain text, `pasteAsPlainText(_:)` validates and then inserts nothing, so ⌘V would do
    /// nothing in the panel. Going through `insertText` keeps undo, the selection and the change
    /// notifications exactly as for typing.
    override func paste(_ sender: Any?) {
        guard isEditable, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        insertText(text, replacementRange: selectedRange())
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }

    // MARK: Changes

    override func didChangeText() {
        super.didChangeText()
        onTextChange?()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onTextChange?()
    }

    override func unmarkText() {
        super.unmarkText()
        onTextChange?()
    }
}
