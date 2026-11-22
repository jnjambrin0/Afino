import AppKit
import PIDesign
import SwiftUI

/// A multi-line editor for the custom instructions: plain text, no smart quotes, dashes or
/// replacements (the text goes to a model as written), typing stops at the 2,000-character limit
/// (`InstructionsText.limit`) and a paste is cut to what fits.
struct InstructionsEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accessibilityLabel: String
    var isEditable = true
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = InstructionsTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: EmberDesign.Spacing.s)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.placeholderString = placeholder
        textView.string = text
        textView.onFocusChange = { focused in
            context.coordinator.focusChanged(focused)
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? InstructionsTextView else { return }
        // Edits made here already reached `text`; anything else (an example chip) is applied.
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.textColor = isEditable ? .labelColor : .tertiaryLabelColor
        textView.placeholderString = placeholder
    }

    /// The editor's font: the body text style.
    static var font: NSFont { .preferredFont(forTextStyle: .body) }

    /// The height of `lines` lines of text plus the editor's insets.
    static func height(lines: Int) -> CGFloat {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return (lineHeight * CGFloat(lines)).rounded(.up) + EmberDesign.Spacing.s * 2
    }

    /// Holds each edit to the limit and reports the text and the focus back to SwiftUI.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InstructionsEditor

        init(_ parent: InstructionsEditor) {
            self.parent = parent
        }

        func focusChanged(_ focused: Bool) {
            if parent.isFocused != focused { parent.isFocused = focused }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }
            guard let allowed = InstructionsText.allowedReplacement(in: textView.string, range: range, replacement: replacement) else {
                NSSound.beep()
                return false
            }
            guard allowed == replacement else {
                // Insert what fits in place of the whole paste; this edit then passes the check.
                textView.insertText(allowed, replacementRange: range)
                NSSound.beep()
                return false
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }
}

/// The editor's text view: draws a placeholder when empty (`NSTextView` has no public one) and
/// reports focus, so the SwiftUI field chrome around it can draw its focus ring.
final class InstructionsTextView: NSTextView {
    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholderString, let font else { return }
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        NSAttributedString(string: placeholderString, attributes: attributes)
            .draw(with: NSRect(origin: origin, size: NSSize(width: bounds.width - origin.x * 2, height: bounds.height)),
                  options: [.usesLineFragmentOrigin])
    }
}
