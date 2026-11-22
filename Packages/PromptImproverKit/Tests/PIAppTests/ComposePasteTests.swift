import AppKit
@testable import PIApp
import Testing

/// ⌘V in the compose input inserts the clipboard's plain text. With the readable types narrowed to
/// plain text, AppKit's own paste inserts nothing, so `ComposeTextView` pastes by hand; this test
/// keeps it that way. It uses the real general pasteboard and restores what was on it.
@Suite(.serialized)
struct ComposePasteTests {
    @Test
    func pasteInsertsPlainText() {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }
        pasteboard.clearContents()
        pasteboard.setString("pasted prompt", forType: .string)

        let textView = ComposeTextView.make(font: .systemFont(ofSize: 15))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let valid = textView.validateUserInterfaceItem(item)
        textView.paste(nil)
        #expect(valid, "Paste menu item validates")
        #expect(textView.string == "pasted prompt")

        // Pasting over a selection replaces it.
        textView.setSelectedRange(NSRange(location: 0, length: 6))
        pasteboard.clearContents()
        pasteboard.setString("línea uno\nlínea dos", forType: .string)
        textView.paste(nil)
        #expect(textView.string == "línea uno\nlínea dos prompt")
    }
}
