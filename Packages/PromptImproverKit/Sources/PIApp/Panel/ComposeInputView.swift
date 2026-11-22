import AppKit
import PIDesign

/// The compose input of the panel: a TextKit 2 text view sitting directly on the glass, with a
/// placeholder, growing from one line to `EmberDesign.Panel.inputMaxLines` and then scrolling.
///
/// It is an AppKit view the panel controller owns from launch and lays over the SwiftUI content
/// itself, so `present()` can make the text view first responder synchronously: `@FocusState` is
/// asynchronous and drops the first keystrokes after the shortcut. The text view is never
/// recreated; the session's draft is pushed into it with `setDraft(_:)` and every edit is reported
/// back with `onDraftChange`, so the two never disagree.
final class ComposeInputView: NSView {
    let textView: ComposeTextView
    private let scrollView = NSScrollView()
    private let font: NSFont
    private let placeholder: String
    private let lineHeight: CGFloat
    private let verticalInset: CGFloat
    private var measuredWidth: CGFloat = 0
    private var showsPlaceholder = true

    /// The height the input wants for its text: one line to `inputMaxLines`, plus its insets
    /// (52 pt for one line, 20 pt more per line).
    private(set) var preferredHeight: CGFloat = EmberDesign.Panel.inputMinHeight
    /// The preferred height changed, from the first value to the second.
    var onPreferredHeightChange: ((_ old: CGFloat, _ new: CGFloat) -> Void)?
    /// Return outside an input method's composition, with the draft as it is. The panel's key map
    /// normally takes Return first; this is the text view's own fallback.
    var onSubmit: ((String) -> Void)?
    /// The user changed the text (typing, pasting, an input method's marked text, Writing Tools).
    /// Not called by `setDraft(_:)`.
    var onDraftChange: ((String) -> Void)?
    /// The view joined a window: the owner may now make the text view first responder.
    var onMoveToWindow: (() -> Void)?

    /// The height of one line of the input's font: what counts as a one-line change.
    var oneLineHeight: CGFloat { lineHeight }

    var draft: String { textView.string }

    init(placeholder: String) {
        self.placeholder = placeholder
        font = NSFont.preferredFont(forTextStyle: .title3)
        lineHeight = ceil(font.ascender - font.descender + font.leading)
        verticalInset = max(0, ((EmberDesign.Panel.inputMinHeight - lineHeight) / 2).rounded(.down))
        textView = ComposeTextView.make(font: font)
        super.init(frame: NSRect(x: 0, y: 0, width: EmberDesign.Panel.width, height: EmberDesign.Panel.inputMinHeight))

        // The vertical inset is the scroll view's margin, not the text container's: a draft
        // longer than ten lines then scrolls inside the inset instead of up to the glass edge.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = PanelLayout.inputTextPadding
        textView.setAccessibilityPlaceholderValue(placeholder)
        textView.setAccessibilityIdentifier(PanelAccessibilityID.composeInput)
        textView.onSubmit = { [weak self] in
            guard let self else { return }
            onSubmit?(draft)
        }
        textView.onTextChange = { [weak self] in self?.textDidChange() }

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.frame = bounds.insetBy(dx: 0, dy: verticalInset)
        scrollView.autoresizingMask = [.width, .height]
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        scrollView.documentView = textView
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMoveToWindow?() }
    }

    // The text view's width decides the line breaks; measure again once it is known or changes.
    override func layout() {
        super.layout()
        let width = textView.frame.width
        if width > 0, width != measuredWidth {
            measuredWidth = width
            updatePreferredHeight()
        }
    }

    /// Lays the text out once before the first show, so TextKit 2, the font and the typesetter
    /// are warm when the first key arrives. Edits the storage directly, which registers no undo
    /// and reaches no delegate; the draft is left as it was.
    func prewarm() {
        layoutSubtreeIfNeeded()
        if textView.string.isEmpty, let storage = textView.textStorage {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Warm up")
            _ = measureContentHeight()
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "")
        }
        updatePreferredHeight()
    }

    /// Shows `draft` (from the session: a recalled draft, Edit Original, a new prompt) with the
    /// caret at its end. Does nothing when the text is already that, so the caret, the selection
    /// and an input method's composition are never disturbed by the echo of the user's own edit.
    func setDraft(_ draft: String) {
        guard draft != textView.string, !textView.hasMarkedText() else { return }
        textView.string = draft
        textView.setSelectedRange(NSRange(location: (draft as NSString).length, length: 0))
        refreshAfterChange()
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    // MARK: Placeholder

    override func draw(_ dirtyRect: NSRect) {
        guard showsPlaceholder else { return }
        // Where the text view puts the first line: its container inset and line padding.
        let origin = NSPoint(x: PanelLayout.inputTextPadding, y: verticalInset)
        (placeholder as NSString).draw(
            at: origin,
            withAttributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor]
        )
    }

    // MARK: Measuring

    private func textDidChange() {
        refreshAfterChange()
        onDraftChange?(textView.string)
    }

    private func refreshAfterChange() {
        let isEmpty = textView.string.isEmpty
        if isEmpty != showsPlaceholder {
            showsPlaceholder = isEmpty
            needsDisplay = true
        }
        updatePreferredHeight()
    }

    private func updatePreferredHeight() {
        let height = max(EmberDesign.Panel.inputMinHeight, measureContentHeight() + 2 * verticalInset)
        guard height != preferredHeight else { return }
        let old = preferredHeight
        preferredHeight = height
        onPreferredHeightChange?(old, height)
    }

    /// The height of the text's lines, from one line to the cap. Lays out only as many
    /// paragraphs as it takes to reach the cap, so a long paste costs no more than ten lines.
    private func measureContentHeight() -> CGFloat {
        let cap = lineHeight * CGFloat(EmberDesign.Panel.inputMaxLines)
        guard let layoutManager = textView.textLayoutManager, measuredWidth > 0 || textView.frame.width > 0 else {
            return lineHeight
        }
        var bottom: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            bottom = fragment.layoutFragmentFrame.maxY
            return bottom < cap
        }
        return min(max(bottom.rounded(.up), lineHeight), cap)
    }
}
