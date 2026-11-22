import AppKit
import SwiftUI

/// Places an AppKit view that its owner created and keeps: SwiftUI never makes or remakes it.
/// The panel's text fields and the result text are such views, so the controller can make them
/// first responder synchronously and their text survives every state change.
struct HostedView: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The view that holds the panel's SwiftUI content. When no text field has the keyboard (a run in
/// flight, a failure) it does, so stray keys are swallowed quietly instead of beeping; the
/// panel's key map has already taken every key that means something.
final class PanelContainerView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {}
}

/// A borderless one-line field drawn straight on the glass (the refine field, the history filter).
/// Owned by the panel controller like the compose input.
final class PanelTextField: NSTextField, NSTextFieldDelegate {
    /// Every edit, with the field's text.
    var onTextChange: ((String) -> Void)?
    /// The field joined a window: the owner may now give it the keyboard.
    var onMoveToWindow: (() -> Void)?

    init(placeholder: String, font: NSFont, identifier: String) {
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        cell?.isScrollable = true
        cell?.wraps = false
        self.font = font
        placeholderString = placeholder
        delegate = self
        setAccessibilityIdentifier(identifier)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMoveToWindow?() }
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(stringValue)
    }

    /// Sets the text from the model without reporting it back.
    func setText(_ text: String) {
        guard stringValue != text else { return }
        stringValue = text
    }
}

/// The API key field: secure, borderless (the card draws its chrome), owned by the controller.
final class PanelSecureField: NSSecureTextField, NSTextFieldDelegate {
    /// Every edit, with the field's text.
    var onTextChange: ((String) -> Void)?
    /// The field joined a window: the owner may now give it the keyboard.
    var onMoveToWindow: (() -> Void)?
    /// The field gained or lost the keyboard (the card draws the focus colour).
    var onFocusChange: ((Bool) -> Void)?

    init(identifier: String) {
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        cell?.isScrollable = true
        cell?.wraps = false
        font = .preferredFont(forTextStyle: .body)
        delegate = self
        setAccessibilityIdentifier(identifier)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMoveToWindow?() }
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(stringValue)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }

    /// Sets the text from the model without reporting it back.
    func setText(_ text: String) {
        guard stringValue != text else { return }
        stringValue = text
    }

    /// The placeholder names the chosen provider, so it changes with the provider.
    func setPlaceholder(_ placeholder: String) {
        guard placeholderString != placeholder else { return }
        placeholderString = placeholder
    }
}
