import AppKit
@testable import PIApp
import PIDesign
import Testing

/// Shared fixtures for the stream view tests and `StreamSnapshotTests`.
@MainActor
enum StreamTestSupport {
    static let prompt = """
    # Role
    You are a senior front-end engineer 👩🏽‍💻 who writes <document> tags and `inline code`.

    ## Steps
    1. Read the <examples> carefully.
    - Keep **every** constraint.
    - Never invent café prices; quote them exactly.

    ```swift
    let greeting = "hello" // # not a heading
    print(greeting)
    ```

    </examples>
    Finish with a one-line summary.\r
    The end. 🇪🇸
    """

    static func makeView(width: CGFloat = 640, height: CGFloat = 400, visible: Bool = false) -> (NSWindow, StreamTextView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let view = StreamTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.reduceMotionOverride = false
        window.contentView = view
        if visible {
            window.orderFrontRegardless()
        }
        return (window, view)
    }

    /// Pumps the main run loop until `condition` holds or `timeout` passes.
    static func pump(timeout: TimeInterval, until condition: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
        }
    }

    /// Feeds `text` in random chunks, as a stream would, pumping between deltas.
    static func stream(_ text: String, into view: StreamTextView, seed: UInt64 = 3, maxChunk: Int = 24, pause: TimeInterval = 0.012, each: () -> Void = {}) {
        let scalars = Array(text.unicodeScalars)
        var random = SplitMix64(seed: seed)
        var given = 0
        while given < scalars.count {
            given = min(scalars.count, given + Int(random.next() % UInt64(maxChunk)) + 1)
            var chunk = String.UnicodeScalarView()
            chunk.append(contentsOf: scalars[..<given])
            view.setText(String(chunk), streaming: true)
            pump(timeout: pause)
            each()
        }
    }

    /// Whether any revealed text is drawn with a partly transparent rendering colour.
    static func hasFadingText(_ view: StreamTextView) -> Bool {
        guard let manager = view.documentTextView.textLayoutManager else { return false }
        // The view sets a rendering colour only on runs that are still fading in.
        var found = false
        manager.enumerateRenderingAttributes(from: manager.documentRange.location, reverse: false) { _, attributes, _ in
            if attributes[.foregroundColor] is NSColor {
                found = true
                return false
            }
            return true
        }
        return found
    }

    static func utf16Equal(_ a: String, _ b: String) -> Bool {
        a.utf16.elementsEqual(b.utf16)
    }
}

/// The result well's text view, driven by real frames in an offscreen window: the paced reveal,
/// exact text, copying, the caret and pinned scrolling.
@Suite(.serialized)
struct StreamTextViewTests {
    private typealias Support = StreamTestSupport

    @Test func streamsAMultiParagraphPromptExactly() {
        let (window, view) = Support.makeView()
        defer { window.close() }
        var heights: [CGFloat] = []
        view.onContentHeightChange = { heights.append($0) }
        view.caretMode = .trailing

        var sawPending = false
        var sawFade = false
        Support.stream(Support.prompt, into: view) {
            sawPending = sawPending || view.hasPendingText
            sawFade = sawFade || Support.hasFadingText(view)
        }
        view.finishStreaming()
        Support.pump(timeout: 1) { !view.hasPendingText }
        Support.pump(timeout: 0.2)

        // The storage holds exactly the model's text, character for character.
        #expect(Support.utf16Equal(view.displayedText, Support.prompt))
        #expect(!view.hasPendingText)
        #expect(sawPending, "text should have been paced, not shown at once")
        #expect(sawFade, "released runs should fade in through rendering attributes")
        #expect(!Support.hasFadingText(view), "every fade should have finished")

        // The height grew with the text and never shrank.
        #expect(heights.count > 3)
        #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 < $1 })
        #expect(heights.last == view.contentHeight)

        // TextKit 2 is still on after everything.
        #expect(view.documentTextView.textLayoutManager != nil)

        // Select All selects exactly the text.
        view.documentTextView.selectAll(nil)
        #expect(view.selectedText.map { Support.utf16Equal($0, Support.prompt) } == true)
        #expect(view.documentTextView.textLayoutManager != nil)
    }

    @Test func textThatIsNotAnExtensionReplacesAtOnce() {
        let (window, view) = Support.makeView()
        defer { window.close() }
        view.setText("", streaming: false)
        view.setText("First version, streamed.", streaming: true)
        Support.pump(timeout: 0.6) { !view.hasPendingText }
        #expect(view.displayedText == "First version, streamed.")

        view.setText("A different version.", streaming: true)
        #expect(view.displayedText == "A different version.")
        #expect(!view.hasPendingText)

        view.setText("Shown at once, not streamed.", streaming: false)
        #expect(view.displayedText == "Shown at once, not streamed.")

        // An extension given with `streaming: false` is shown at once too.
        view.setText("Shown at once, not streamed. And more.", streaming: false)
        #expect(view.displayedText == "Shown at once, not streamed. And more.")
        #expect(view.documentTextView.textLayoutManager != nil)
    }

    @Test func streamedTextWaitsForTicks() {
        let (window, view) = Support.makeView()
        defer { window.close() }
        view.setText(String(repeating: "paced words ", count: 40), streaming: true)
        // Nothing is shown until the first tick…
        #expect(view.displayedText.isEmpty)
        Support.pump(timeout: 0.05)
        // …then only part of it.
        #expect(!view.displayedText.isEmpty)
        #expect(view.hasPendingText)
        Support.pump(timeout: 1) { !view.hasPendingText }
        #expect(view.displayedText == view.text)
    }

    @Test func finishStreamingDrainsWithinAQuarterSecond() {
        let (window, view) = Support.makeView()
        defer { window.close() }
        view.setText(String(repeating: "lorem ipsum dolor ", count: 200), streaming: true)
        Support.pump(timeout: 0.04)
        #expect(view.hasPendingText)
        let start = Date()
        view.finishStreaming()
        Support.pump(timeout: 1) { !view.hasPendingText }
        #expect(!view.hasPendingText)
        #expect(Date().timeIntervalSince(start) < StreamLocalTokens.maximumLag + 0.1)
    }

    @Test func copyPutsPlainTextOnly() {
        let (window, view) = Support.makeView()
        defer { window.close() }
        view.setText(Support.prompt, streaming: false)
        let textView = view.documentTextView
        #expect(textView.writablePasteboardTypes == [.string])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        // Nothing selected: Copy writes nothing.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!textView.writeSelectedText(to: pasteboard))

        textView.selectAll(nil)
        #expect(textView.writeSelectedText(to: pasteboard))
        #expect(Self.isPlainTextOnly(pasteboard))
        #expect(pasteboard.string(forType: .string).map { Support.utf16Equal($0, Support.prompt) } == true)

        textView.setSelectedRange(NSRange(location: 2, length: 4))
        #expect(textView.writeAllText(to: pasteboard))
        #expect(Self.isPlainTextOnly(pasteboard))
        #expect(pasteboard.string(forType: .string).map { Support.utf16Equal($0, Support.prompt) } == true)
        #expect(textView.textLayoutManager != nil)
    }

    /// Plain text only: the pasteboard lists the UTF-8 plain-text type, plus its legacy alias.
    private static func isPlainTextOnly(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        let legacyPlainText = NSPasteboard.PasteboardType("NSStringPboardType")
        return types.contains(.string) && types.allSatisfy { $0 == .string || $0 == legacyPlainText }
    }

    @Test func contextMenuOffersCopyAndCopyAllOnly() throws {
        let (window, view) = Support.makeView()
        defer { window.close() }
        view.setText("Some text", streaming: false)
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let menu = try #require(view.documentTextView.menu(for: event))
        #expect(menu.items.count == 2)
        #expect(menu.items.map(\.title) == [AppStrings.copy, StreamDocumentTextView.copyAllTitle])
        #expect(menu.items[0].isEnabled == false)
        #expect(menu.items[1].isEnabled == true)
    }

    @Test func behavesAsAReadOnlyPlainTextArea() {
        let (window, view) = Support.makeView()
        defer { window.close() }
        let textView = view.documentTextView
        #expect(!textView.isEditable)
        #expect(textView.isSelectable)
        #expect(!textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(!textView.isAutomaticDashSubstitutionEnabled)
        #expect(!textView.isAutomaticTextReplacementEnabled)
        #expect(!textView.isContinuousSpellCheckingEnabled)
        #expect(!textView.isAutomaticLinkDetectionEnabled)
        #expect(!textView.drawsBackground)

        view.setAccessibilityLabel("Improved prompt")
        view.setText("Hello there", streaming: false)
        #expect(!view.isAccessibilityElement())
        #expect(textView.accessibilityRole() == .textArea)
        #expect(textView.accessibilityLabel() == "Improved prompt")
        #expect(textView.accessibilityValue() == "Hello there")
        #expect(textView.textLayoutManager != nil)
    }

    @Test func dimmingFadesTheText() {
        let (window, view) = Support.makeView()
        defer { window.close() }
        view.setText("Previous version", streaming: false)
        view.isDimmed = true
        Support.pump(timeout: 0.5) { view.documentTextView.alphaValue == StreamLocalTokens.dimmedTextOpacity }
        #expect(abs(view.documentTextView.alphaValue - StreamLocalTokens.dimmedTextOpacity) < 0.01)
        view.isDimmed = false
        Support.pump(timeout: 0.5) { view.documentTextView.alphaValue == 1 }
        #expect(view.documentTextView.alphaValue == 1)
    }

    @Test func caretSitsAtTheInsertionPointAndTrailsTheText() throws {
        let (window, view) = Support.makeView()
        defer { window.close() }
        #expect(view.caretFrame == nil)
        view.caretMode = .breathing
        let empty = try #require(view.caretFrame)
        // Top-left inside the padding (this view is not flipped: y counts from the bottom).
        #expect(empty.minX == EmberDesign.Panel.wellHorizontalPadding)
        #expect(abs(view.bounds.height - empty.maxY - EmberDesign.Panel.wellVerticalPadding) < 1)
        #expect(empty.width == EmberDesign.Caret.width)

        view.caretMode = .trailing
        view.setText("Hello", streaming: true)
        Support.pump(timeout: 0.5) { !view.hasPendingText }
        let trailing = try #require(view.caretFrame)
        #expect(trailing.minX > empty.minX + 20)
        #expect(abs(trailing.minY - empty.minY) < 1, "same line")

        view.setText("Hello\n", streaming: true)
        Support.pump(timeout: 0.5) { !view.hasPendingText }
        let nextLine = try #require(view.caretFrame)
        #expect(nextLine.minX == empty.minX)
        #expect(nextLine.maxY < trailing.minY, "the caret moved down to the new line")

        view.caretMode = .hidden
        #expect(view.caretFrame == nil)
    }

    @Test func pinsToTheBottomAndReleasesWhenScrolledUp() {
        let (window, view) = Support.makeView(width: 400, height: 120)
        defer { window.close() }
        let lines = (1...30).map { "Line \($0) of a long streamed answer." }.joined(separator: "\n")
        view.setText("", streaming: false)
        view.caretMode = .trailing
        Support.stream(lines, into: view, maxChunk: 40)
        Support.pump(timeout: 1.5) { !view.hasPendingText && abs(view.scrollOffset - view.maximumScrollOffset) < 1 }
        #expect(view.maximumScrollOffset > 100)
        #expect(abs(view.scrollOffset - view.maximumScrollOffset) < 1, "pinned to the newest line")
        #expect(view.isPinnedToBottom)
        #expect(!view.isShowingJumpToLatest)

        // The caret layer sits after the last character even though that text was laid out
        // below the viewport while it streamed.
        if let expected = view.caretRect().map({ view.convert($0, from: view.documentTextView) }), let caret = view.caretFrame {
            #expect(abs(caret.minY - expected.minY) < 0.5 && abs(caret.minX - expected.minX) < 0.5, "caret \(caret) expected \(expected)")
            #expect(view.bounds.contains(caret), "the caret is in sight")
        } else {
            Issue.record("the caret should be showing")
        }

        // Scrolling up while the stream is live releases the pin and offers the way back.
        for _ in 0..<3 {
            view.scrollLine(down: false)
        }
        #expect(view.maximumScrollOffset - view.scrollOffset > EmberDesign.Stream.unpinDistance)
        #expect(!view.isPinnedToBottom)
        #expect(view.isShowingJumpToLatest)

        // New text arrives below without moving the viewport; the end of the stream moves nothing.
        let offset = view.scrollOffset
        view.setText(lines + "\nOne more line.\nAnd another.", streaming: true)
        Support.pump(timeout: 0.6) { !view.hasPendingText }
        view.finishStreaming()
        Support.pump(timeout: 0.3)
        #expect(view.scrollOffset == offset)
        #expect(view.isShowingJumpToLatest)

        view.scrollToEnd()
        #expect(view.isPinnedToBottom)
        #expect(!view.isShowingJumpToLatest)
        #expect(abs(view.scrollOffset - view.maximumScrollOffset) < 1)

        // Rereading a finished result: the pin releases, but there is nothing to jump to.
        for _ in 0..<3 {
            view.scrollLine(down: false)
        }
        #expect(!view.isPinnedToBottom)
        #expect(!view.isShowingJumpToLatest)
        #expect(view.documentTextView.textLayoutManager != nil)
    }

    @Test func aOneShotTextIsScrollableAtOnce() {
        let (window, view) = Support.makeView(width: 400, height: 120)
        defer { window.close() }
        view.setText((1...30).map { "Line \($0)" }.joined(separator: "\n"), streaming: false)
        #expect(view.maximumScrollOffset > 100)
        #expect(view.scrollOffset == 0, "a result shown at once starts at its top")
        view.scrollToEnd()
        #expect(abs(view.scrollOffset - view.maximumScrollOffset) < 1)
    }

    @Test func doesNotScrollWhileTheOwnerGrowsTheView() {
        let (window, view) = Support.makeView(width: 400, height: 60)
        defer { window.close() }
        // The owner grows the view to fit its content with the panel's follow.
        let animator = PanelHeightAnimator { height in
            window.setContentSize(NSSize(width: 400, height: height))
        }
        animator.reduceMotionOverride = false
        animator.setHeight(60, transition: .instant)
        view.onContentHeightChange = { height in
            animator.setHeight(height, transition: .follow)
        }
        var maximumOffsetSeen: CGFloat = 0
        let lines = (1...8).map { "Growing line \($0)." }.joined(separator: "\n")
        Support.stream(lines, into: view, maxChunk: 12) {
            maximumOffsetSeen = max(maximumOffsetSeen, view.scrollOffset)
        }
        view.finishStreaming()
        Support.pump(timeout: 1) { !view.hasPendingText && !animator.isAnimating }
        #expect(maximumOffsetSeen == 0, "the view should never scroll while it can grow")
        #expect(view.scrollOffset == 0)
        #expect(view.bounds.height == view.contentHeight)
    }
}
