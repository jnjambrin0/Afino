import AppKit

/// Where a finished prompt goes. A protocol so tests can count writes: the clipboard must be
/// written exactly once per finished version, and never with a partial or refused result.
public protocol ClipboardWriting: AnyObject {
    /// Replaces the clipboard's contents with `text`.
    func write(_ text: String)
}

/// The general pasteboard. The text is written as plain text with no "transient" marker: the
/// user wants clipboard managers to keep an improved prompt.
public final class SystemClipboard: ClipboardWriting {
    public init() {}

    public func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
