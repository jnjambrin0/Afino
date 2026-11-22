import AppKit
import PIDesign
import QuartzCore

/// The result well's text: read-only, selectable, and revealed at an even pace while the engine
/// writes.
///
/// - Paced reveal: streamed text waits in a `StreamRevealBuffer` and leaves in small runs every
///   `EmberDesign.Stream.drainInterval`, whole graphemes, preferring word ends, never more than
///   `StreamLocalTokens.maximumLag` (about 250 ms) behind. The text storage only ever holds exact
///   final characters.
/// - Fade-in without reflow: each run fades 0.35 → 0.7 → 1 over `EmberDesign.Stream.fadeDuration`
///   through TextKit 2 rendering attributes, which never touch layout.
/// - Caret: an accent-coloured `CALayer` (`StreamCaret`) after the last revealed character,
///   driven by `caretMode`.
/// - Height: `contentHeight` follows the revealed text and is reported through
///   `onContentHeightChange`.
/// - Pinned scrolling: once the well stops growing and text runs past its bottom, the view
///   follows the newest line smoothly. Scrolling up more than `EmberDesign.Stream.unpinDistance`
///   releases it and, while text is still arriving, shows "Jump to latest".
/// - Edge fade: an alpha mask, up to `EmberDesign.Stream.edgeFade` (12 pt) deep, on each edge
///   where content is clipped (`StreamEdgeMask`).
/// - Syntax tint: `PromptSyntaxStyler` attributes only; no character is hidden or replaced.
///
/// Draws no background: the well behind it belongs to the owner. TextKit 2 must stay on, so
/// nothing here reads `layoutManager`.
final class StreamTextView: NSView {
    /// What the caret does; the owner sets it from the session's phase.
    enum CaretMode: Equatable {
        /// No caret.
        case hidden
        /// Waiting for the first text: the caret breathes at the insertion point.
        case breathing
        /// Text is arriving: the caret trails the last character, solid while runs are released
        /// and breathing once they pause for `StreamLocalTokens.caretIdleDelay`.
        case trailing
    }

    var caretMode: CaretMode = .hidden {
        didSet {
            guard caretMode != oldValue else { return }
            updateCaretState(at: CACurrentMediaTime())
            updateCaretPosition()
            scheduleTicksIfNeeded()
        }
    }

    /// The height the content wants (text plus the well's vertical padding), reported whenever it
    /// changes so the panel can grow.
    var onContentHeightChange: ((CGFloat) -> Void)?

    /// While a refinement is in flight the previous version stays visible but dimmed.
    var isDimmed = false {
        didSet {
            guard isDimmed != oldValue else { return }
            let alpha: CGFloat = isDimmed ? StreamLocalTokens.dimmedTextOpacity : 1
            NSAnimationContext.runAnimationGroup { context in
                context.duration = EmberDesign.Motion.contentCrossfadeDuration
                textView.animator().alphaValue = alpha
            }
        }
    }

    /// Overrides the system Reduce Motion setting (for tests).
    var reduceMotionOverride: Bool?

    /// Whether the view keeps the newest text in sight (`false` once the person scrolls up).
    var isPinnedToBottom: Bool { anchor == .pinned }

    /// Whether "Jump to latest" is showing.
    var isShowingJumpToLatest: Bool { jumpPill.isShown }

    /// The full text given so far, including what is still waiting to be revealed.
    var text: String { buffer.text }

    /// The revealed text (what the view shows, and what selection and copy see).
    var displayedText: String { textView.string }

    /// Whether streamed text is still waiting to be revealed.
    var hasPendingText: Bool { !buffer.isDrained }

    /// The text view inside, for tests to inspect. Never read its `layoutManager`.
    var documentTextView: StreamDocumentTextView { textView }

    /// The scroll offset, 0 at the top.
    var scrollOffset: CGFloat { currentOffset }

    /// The largest scroll offset the text allows.
    var maximumScrollOffset: CGFloat { maximumOffset }

    /// The caret's frame in this view's coordinates, `nil` while it is hidden.
    var caretFrame: CGRect? {
        guard caret.state != .hidden else { return nil }
        return convert(caret.frame, from: scrollView.contentView)
    }

    private enum Anchor {
        /// Following the newest text (when it runs past the bottom).
        case pinned
        /// The person scrolled away from the bottom.
        case detached
        /// Static content (shown at once, not streamed): nothing to follow.
        case free
    }

    private let scrollView = StreamScrollView()
    private let textView = StreamDocumentTextView.make()
    private let caret = StreamCaret()
    private let edgeMask = CAGradientLayer()
    private lazy var jumpPill = StreamJumpPillHost(title: StreamJumpPill.localizedTitle) { [weak self] in
        self?.scrollToEnd()
    }

    private var buffer = StreamRevealBuffer()
    private var fades = StreamFadeTracker()
    /// Where the styler resumes (the start of the last line in the storage) and its state there.
    private var styledLineStart = 0
    private var styledState = PromptSyntaxStyler.State()
    /// True from the first streamed text until the drain after `finishStreaming()` ends.
    /// While text is arriving there is no scroller: it would keep resizing and jumping as the
    /// text grows. It comes back (when there is something to scroll) once the stream has ended.
    /// Scrolling itself works throughout.
    private var isStreaming = false {
        didSet {
            guard isStreaming != oldValue else { return }
            scrollView.hasVerticalScroller = !isStreaming
        }
    }
    /// Shows whatever is still pending once `StreamLocalTokens.maximumLag` has passed after
    /// `finishStreaming()`, even if frames stop arriving.
    private var finishFallback: Task<Void, Never>?

    private lazy var ticker = FrameTicker { [weak self] time in
        self?.step(at: time)
    }
    private var lastFrameTime: CFTimeInterval?
    private var lastDrainTime: CFTimeInterval?
    private var lastReleaseTime: CFTimeInterval?

    /// The height last passed to `onContentHeightChange`.
    private var reportedContentHeight: CGFloat?
    /// The text's laid-out height, valid while `isLayoutCurrent`.
    private var laidOutTextHeight: CGFloat = 0
    /// Cleared by every change to the text or its width; `layOut()` sets it.
    private var isLayoutCurrent = false
    private var anchor: Anchor = .pinned {
        didSet {
            if anchor != .detached {
                detachedWhileStreaming = false
            }
        }
    }
    /// Whether the person scrolled away while text was arriving (see `updateJumpPill()`).
    private var detachedWhileStreaming = false
    /// Set while this view moves the clip view itself, so the bounds notification that follows
    /// is not taken for the person scrolling.
    private var isScrollingProgrammatically = false
    /// The unrounded scroll offset of a follow in progress.
    private var followOffset: Double?
    /// When the owner last changed the view's height.
    private var lastHeightChange: CFTimeInterval = 0
    /// When the text first became taller than the view (in the current stretch of overflow).
    private var overflowSince: CFTimeInterval?
    /// The height the owner stops growing the view at, learnt the first time text runs past the
    /// bottom of a view that has stopped growing. Pinned scrolling follows at once at that
    /// height; below it, the owner's growth reveals new lines and the view does not scroll.
    private var heightCap: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // The scroller shows only when there is something to scroll. The text width never
        // depends on it (see `updateTextContainerWidth()`), so it can come and go freely.
        scrollView.autohidesScrollers = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.textContainer?.widthTracksTextView = false
        updateTextContainerWidth()
        scrollView.onUserScroll = { [weak self] in
            self?.userDidScroll()
        }
        addSubview(scrollView)

        let clipView = scrollView.contentView
        clipView.drawsBackground = false
        clipView.wantsLayer = true
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        clipView.layer?.addSublayer(caret.layer)
        clipView.layer?.mask = edgeMask
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferredScrollerStyleDidChange(_:)),
            name: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil
        )

        addSubview(jumpPill)

        caret.setColor(for: effectiveAppearance)
        textView.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: StreamTextStyle.baseAttributes))
        updateLayoutDependents()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Interface

    /// The laid-out height of everything shown, including vertical padding.
    var contentHeight: CGFloat {
        if !isLayoutCurrent {
            layOut()
        }
        return laidOutTextHeight + EmberDesign.Panel.wellVerticalPadding * 2
    }

    /// Shows `text`. With `streaming`, text that extends what is already shown is revealed at the
    /// stream pace; anything else replaces the content at once.
    func setText(_ text: String, streaming: Bool) {
        if streaming {
            switch buffer.receive(text) {
            case .unchanged:
                return
            case .appended:
                isStreaming = true
                if anchor == .free {
                    anchor = distanceFromBottom <= EmberDesign.Stream.unpinDistance ? .pinned : .detached
                }
                scheduleTicksIfNeeded()
            case .replaced:
                isStreaming = true
                replaceContent(streaming: true)
                scheduleTicksIfNeeded()
            }
            return
        }

        let isSameText = text.utf8.count == buffer.text.utf8.count && StreamRevealBuffer.hasPrefix(text, buffer.text)
        if isSameText, finishFallback != nil, !buffer.isDrained {
            // `finishStreaming()` is already revealing the rest of this very text: let it end at
            // its own pace instead of cutting the reveal short. It completes the stream itself.
            return
        }
        let wasStreaming = isStreaming
        isStreaming = false
        finishFallback?.cancel()
        finishFallback = nil
        if isSameText {
            // The same text, final: show whatever is still pending, at once.
            if let release = buffer.flush() {
                append(release, at: CACurrentMediaTime(), fading: false)
            }
            restyleTail(provisional: false)
            if wasStreaming {
                announceValueChange()
            }
            return
        }
        buffer.reset(to: text)
        replaceContent(streaming: false)
    }

    /// Ends the stream: whatever is still pending is shown within `StreamLocalTokens.maximumLag`
    /// (a quarter of a second).
    func finishStreaming() {
        buffer.finish()
        guard !buffer.isDrained else {
            completeStream()
            return
        }
        scheduleTicksIfNeeded()
        // Frames may pause (an occluded window); the deadline holds regardless.
        finishFallback?.cancel()
        finishFallback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(StreamLocalTokens.maximumLag))
            guard !Task.isCancelled, let self else { return }
            if let release = self.buffer.flush() {
                self.append(release, at: CACurrentMediaTime(), fading: false)
            }
            self.completeStream()
        }
    }

    /// The selected text, or `nil` when nothing is selected.
    var selectedText: String? {
        textView.selectedPlainText
    }

    /// Scrolls to the end and follows new text again.
    func scrollToEnd() {
        anchor = .pinned
        followOffset = nil
        scroll(to: maximumOffset, programmatically: true)
        updateJumpPill()
    }

    /// Scrolls by one line (the panel's ↑ and ↓ while a result is showing).
    func scrollLine(down: Bool) {
        let step = StreamTextStyle.bodyLineHeight + EmberDesign.Typography.resultLineSpacing
        let target = min(max(currentOffset + (down ? step : -step), 0), maximumOffset)
        followOffset = nil
        scroll(to: target, programmatically: false)
        userDidScroll()
    }

    // MARK: Accessibility

    // The text view is the accessibility element (a text area); this view is only its
    // container and forwards its name to it.

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func setAccessibilityLabel(_ accessibilityLabel: String?) {
        textView.setAccessibilityLabel(accessibilityLabel)
    }

    override func accessibilityLabel() -> String? {
        textView.accessibilityLabel()
    }

    /// The text area's name for VoiceOver (forwarded to the text view as its label).
    override func setAccessibilityTitle(_ accessibilityTitle: String?) {
        textView.setAccessibilityLabel(accessibilityTitle)
    }

    override func accessibilityTitle() -> String? {
        textView.accessibilityLabel()
    }

    // MARK: Content

    private var storage: NSTextStorage? { textView.textStorage }

    /// Replaces the storage with the buffer's text, revealed and styled at once.
    private func replaceContent(streaming: Bool) {
        guard let storage else { return }
        let newText = buffer.text
        let isRevision = Self.isRevision(of: storage.string, by: newText)
        clearFades()

        isScrollingProgrammatically = true
        isLayoutCurrent = false
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: newText, attributes: StreamTextStyle.baseAttributes))
        styledLineStart = 0
        styledState = PromptSyntaxStyler.State()
        restyle(storage, provisional: streaming)
        storage.endEditing()
        isScrollingProgrammatically = false

        if !isRevision {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            followOffset = nil
            anchor = streaming ? .pinned : .free
        }
        textDidChange(at: CACurrentMediaTime(), released: false)
        if !isRevision {
            scroll(to: 0, programmatically: true)
        } else if anchor == .pinned, contentRunsPastBottom {
            scroll(to: maximumOffset, programmatically: true)
        }
        updateJumpPill()
        if !streaming {
            announceValueChange()
        }
    }

    /// Whether `new` keeps everything `old` showed apart from trailing whitespace (a final
    /// cleanup that trims or adjusts the end), so the scroll position and selection can stay.
    private static func isRevision(of old: String, by new: String) -> Bool {
        guard !old.isEmpty else { return false }
        let kept = old.utf16.reversed().drop { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }.count
        return new.utf16.starts(with: old.utf16.prefix(kept)) && kept > 0
    }

    private func append(_ release: StreamRevealBuffer.Release, at time: CFTimeInterval, fading: Bool) {
        guard let storage else { return }
        isLayoutCurrent = false
        storage.beginEditing()
        storage.append(NSAttributedString(string: release.text, attributes: StreamTextStyle.baseAttributes))
        restyle(storage, provisional: !(buffer.isDrained && buffer.isFinishing) && isStreaming)
        storage.endEditing()
        if fading {
            fades.add(release.utf16Range, at: time)
        }
        lastReleaseTime = time
        textDidChange(at: time, released: true)
    }

    /// Restyles from the start of the storage's last line: text added later can only change that
    /// line and what follows it.
    private func restyle(_ storage: NSTextStorage, provisional: Bool) {
        let range = NSRange(location: styledLineStart, length: storage.length - styledLineStart)
        guard range.length > 0 else { return }
        let tail = storage.mutableString.substring(with: range)
        let result = PromptSyntaxStyler.style(tail, from: styledState, provisionalTail: provisional)
        StreamTextStyle.apply(result.spans, to: storage, in: range)
        styledLineStart += result.lastLineStart
        styledState = result.stateAtLastLine
    }

    /// Restyles the last line on its own (as final text once the stream ends) and refreshes the
    /// caret and the fades, which depend on its layout.
    private func restyleTail(provisional: Bool) {
        guard let storage, storage.length > styledLineStart else { return }
        isLayoutCurrent = false
        storage.beginEditing()
        restyle(storage, provisional: provisional)
        storage.endEditing()
        layOut()
        updateCaretPosition()
        applyFades()
    }

    /// After the storage changed: lay out, report the height, move the caret, then set the fades
    /// (the newest run's included) and the edge mask.
    private func textDidChange(at time: CFTimeInterval, released: Bool) {
        layOut()
        reportContentHeightIfChanged(at: time)
        if released {
            updateCaretState(at: time)
        }
        updateCaretPosition()
        // Last: repainting the fades invalidates the tail's drawing (not its metrics).
        applyFades()
        updateEdgeMask()
    }

    /// Lays the text out once per change and sizes the document to it.
    private func layOut() {
        guard let manager = textView.textLayoutManager else { return }
        // Resizing the document can clamp the scroll offset: that is not the person scrolling.
        let wasProgrammatic = isScrollingProgrammatically
        isScrollingProgrammatically = true
        defer { isScrollingProgrammatically = wasProgrammatic }
        // TextKit 2 sizes the document in its viewport pass, normally at display time, from
        // estimates for text outside the viewport. The scroll range, the height and the caret
        // must be exact now, so: the viewport pass, then real layout for everything…
        manager.textViewportLayoutController.layoutViewport()
        manager.ensureLayout(for: manager.documentRange)
        laidOutTextHeight = max(ceil(manager.usageBoundsForTextContainer.height), StreamTextStyle.bodyLineHeight)
        isLayoutCurrent = true
        // …and the document takes that height (TextKit settles on the same one).
        let height = max(laidOutTextHeight + EmberDesign.Panel.wellVerticalPadding * 2, scrollView.contentView.bounds.height)
        if textView.frame.height != height {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: height))
        }
    }

    private func reportContentHeightIfChanged(at time: CFTimeInterval) {
        // Nothing is recorded until someone listens, so the first listener hears the height.
        guard let onContentHeightChange else { return }
        let height = contentHeight
        guard height != reportedContentHeight else { return }
        reportedContentHeight = height
        onContentHeightChange(height)
    }

    // MARK: Frames

    /// Whether anything still needs frames: pending text, a run fading in, a solid caret that
    /// must go back to breathing, or a pinned view that has not reached the bottom.
    private var wantsTicks: Bool {
        if !buffer.isDrained || !fades.isEmpty {
            return true
        }
        if caretMode == .trailing, caret.state == .solid {
            return true
        }
        return anchor == .pinned && contentRunsPastBottom && (followOffset != nil || currentOffset < maximumOffset - Self.scrollSnap)
    }

    private func scheduleTicksIfNeeded() {
        guard wantsTicks else { return }
        guard !ticker.isRunning else { return }
        lastFrameTime = nil
        ticker.start(.view(self))
    }

    private func step(at time: CFTimeInterval) {
        let dt = min(
            max(time - (lastFrameTime ?? time - StreamLocalTokens.nominalFrameInterval), 0),
            StreamLocalTokens.maximumFrameStep
        )
        lastFrameTime = time

        if !buffer.isDrained {
            drainIfDue(at: time)
        }
        if isStreaming, buffer.isFinishing, buffer.isDrained {
            completeStream()
        }

        let (changed, finished) = fades.advance(to: time)
        if changed {
            removeFades(finished)
            applyFades()
        }

        updateCaretState(at: time)
        followIfPinned(at: time, dt: dt)
        updateJumpPill()

        if !wantsTicks {
            ticker.stop()
            lastFrameTime = nil
        }
    }

    private func drainIfDue(at time: CFTimeInterval) {
        let interval = EmberDesign.Stream.drainInterval
        if let last = lastDrainTime, time - last < interval * (1 - Self.drainPhaseTolerance) {
            return
        }
        // Keep the phase (an even beat), unless frames stalled.
        if let last = lastDrainTime, time - last < interval * 2 {
            lastDrainTime = last + interval
        } else {
            lastDrainTime = time
        }
        if let release = buffer.tick() {
            append(release, at: time, fading: true)
        }
    }

    /// Everything is shown after `finishStreaming()`: the last line takes its final style and
    /// VoiceOver hears the new value.
    private func completeStream() {
        finishFallback?.cancel()
        finishFallback = nil
        guard isStreaming else { return }
        isStreaming = false
        lastDrainTime = nil
        restyleTail(provisional: false)
        announceValueChange()
    }

    private func announceValueChange() {
        NSAccessibility.post(element: textView, notification: .valueChanged)
    }

    // MARK: Fades (rendering attributes: no layout)

    private func applyFades() {
        guard let manager = textView.textLayoutManager, let storage, !fades.isEmpty else { return }
        let appearance = effectiveAppearance
        var touched: [NSRange] = []
        for run in fades.runs {
            let range = NSIntersectionRange(run.range, NSRange(location: 0, length: storage.length))
            guard range.length > 0 else { continue }
            storage.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
                guard let textRange = textRange(for: subrange) else { return }
                let base = (value as? NSColor) ?? .labelColor
                let color = Self.resolve(base, in: appearance, alpha: run.alpha)
                manager.setRenderingAttributes([.foregroundColor: color], for: textRange)
            }
            touched.append(range)
        }
        repaint(touched)
    }

    private func removeFades(_ ranges: [NSRange]) {
        guard let manager = textView.textLayoutManager, let storage else { return }
        var touched: [NSRange] = []
        for range in ranges {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            guard clamped.length > 0, let textRange = textRange(for: clamped) else { continue }
            manager.removeRenderingAttribute(.foregroundColor, for: textRange)
            touched.append(clamped)
        }
        repaint(touched)
    }

    /// TextKit 2 applies rendering attributes when it lays a paragraph out, so a paragraph that
    /// is already on screen keeps its old colours until something invalidates it. An
    /// attribute-only edit with no actual change does exactly that: the characters, their
    /// attributes and the layout stay the same; only the drawing is redone.
    private func repaint(_ ranges: [NSRange]) {
        guard let storage, !ranges.isEmpty else { return }
        storage.beginEditing()
        for range in ranges where NSMaxRange(range) <= storage.length {
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
        }
        storage.endEditing()
    }

    private func clearFades() {
        removeFades(fades.removeAll())
    }

    private static func resolve(_ color: NSColor, in appearance: NSAppearance, alpha: CGFloat) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved.withAlphaComponent(resolved.alphaComponent * alpha)
    }

    private func textRange(for range: NSRange) -> NSTextRange? {
        guard let content = textView.textContentStorage else { return nil }
        let documentStart = content.documentRange.location
        guard let start = content.location(documentStart, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }

    // MARK: Caret

    private var reducesMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateCaretState(at time: CFTimeInterval) {
        switch caretMode {
        case .hidden:
            caret.hide()
        case .breathing:
            caret.breathe(reduceMotion: reducesMotion)
        case .trailing:
            let recent = lastReleaseTime.map { time - $0 < StreamLocalTokens.caretIdleDelay } ?? false
            if recent {
                if caret.state != .solid {
                    caret.solid()
                }
            } else {
                caret.breathe(reduceMotion: reducesMotion)
            }
        }
    }

    private func updateCaretPosition() {
        guard let rect = caretRect() else { return }
        // The caret lives in the clip view's layer, whose coordinates are the document's.
        let origin = textView.convert(rect.origin, to: scrollView.contentView)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caret.frame = CGRect(origin: origin, size: rect.size)
        CATransaction.commit()
    }

    /// The caret's rect in the text view: after the last revealed character, as tall as that
    /// character's line of glyphs (line spacing excluded).
    func caretRect() -> CGRect? {
        let inset = textView.textContainerOrigin
        let width = EmberDesign.Caret.width
        guard let manager = textView.textLayoutManager, let storage, storage.length > 0 else {
            let font = StreamTextStyle.bodyFont
            return CGRect(x: inset.x, y: inset.y, width: width, height: ceil(font.ascender - font.descender))
        }
        let font = (storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont) ?? StreamTextStyle.bodyFont
        let lastUnit = storage.mutableString.character(at: storage.length - 1)
        let lineFont = lastUnit == 0x0A || lastUnit == 0x0D ? StreamTextStyle.bodyFont : font
        // The caret needs real positions, not the viewport pass's estimates: lay out the whole
        // text if it changed, and the last paragraph in any case (repainting a fade invalidates
        // its drawing).
        if !isLayoutCurrent {
            layOut()
        }
        if let last = textRange(for: NSRange(location: storage.length - 1, length: 1)) {
            manager.ensureLayout(for: last)
        }
        let end = manager.documentRange.endLocation
        var segment: CGRect?
        var baseline: CGFloat = 0
        manager.enumerateTextSegments(in: NSTextRange(location: end), type: .standard, options: [.rangeNotRequired]) { _, frame, position, _ in
            segment = frame
            baseline = position
            return false
        }
        guard let segment else { return nil }
        let top = segment.minY + baseline - lineFont.ascender
        // A little air after a character; none at the start of a line.
        let gap = segment.minX > 0 ? StreamLocalTokens.caretGap : 0
        return CGRect(
            x: inset.x + segment.minX + gap,
            y: inset.y + top,
            width: width,
            height: ceil(lineFont.ascender - lineFont.descender)
        )
    }

    // MARK: Scrolling

    private var clipHeight: CGFloat { scrollView.contentView.bounds.height }
    private var documentHeight: CGFloat { textView.frame.height }
    private var currentOffset: CGFloat { scrollView.contentView.bounds.origin.y }
    private var maximumOffset: CGFloat { max(documentHeight - clipHeight, 0) }
    private var distanceFromBottom: CGFloat { max(maximumOffset - currentOffset, 0) }
    private var contentRunsPastBottom: Bool { documentHeight > clipHeight + Self.scrollSnap }

    private func scroll(to offset: CGFloat, programmatically: Bool) {
        let clipView = scrollView.contentView
        let scale = window?.backingScaleFactor ?? 1
        let y = CGFloat(PanelHeightMath.roundedToPixel(Double(offset), scale: Double(scale)))
        guard y != clipView.bounds.origin.y else { return }
        let wasProgrammatic = isScrollingProgrammatically
        isScrollingProgrammatically = programmatically || wasProgrammatic
        clipView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clipView)
        isScrollingProgrammatically = wasProgrammatic
        updateEdgeMask()
    }

    /// Keeps the newest line in sight while pinned, once the view has stopped growing.
    private func followIfPinned(at time: CFTimeInterval, dt: CFTimeInterval) {
        if contentRunsPastBottom {
            overflowSince = overflowSince ?? time
        } else {
            overflowSince = nil
        }
        guard anchor == .pinned, contentRunsPastBottom, !scrollView.isUserInteracting else {
            followOffset = nil
            return
        }
        let target = Double(maximumOffset)
        let current = followOffset ?? Double(currentOffset)
        guard target - current > Double(Self.scrollSnap) || followOffset != nil else { return }
        guard viewHasStoppedGrowing(at: time) else { return }
        if reducesMotion {
            followOffset = nil
            scroll(to: CGFloat(target), programmatically: true)
            return
        }
        var next = PanelHeightMath.followStep(
            value: current,
            target: target,
            dt: dt,
            timeConstant: EmberDesign.Stream.followTimeConstant
        )
        if abs(target - next) < PanelHeightMath.followSnapDistance {
            next = target
            followOffset = nil
        } else {
            followOffset = next
        }
        scroll(to: CGFloat(next), programmatically: true)
    }

    /// Below the owner's cap the panel grows to show new lines (the view must not scroll then, or
    /// the text would rise and fall back); at the cap, the view scrolls. The cap is learnt the
    /// first time the text stays taller than the view for `growthSettleDelay` without the view
    /// growing in response.
    private func viewHasStoppedGrowing(at time: CFTimeInterval) -> Bool {
        if let heightCap, abs(bounds.height - heightCap) < Self.scrollSnap {
            return true
        }
        guard let overflowSince,
              time - max(lastHeightChange, overflowSince) > StreamLocalTokens.growthSettleDelay else {
            return false
        }
        heightCap = bounds.height
        return true
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        updateEdgeMask()
        guard !isScrollingProgrammatically else { return }
        userDidScroll()
    }

    /// The person scrolled: release the pin once they are more than `unpinDistance` from the
    /// bottom, take it back when they return to the bottom.
    private func userDidScroll() {
        followOffset = nil
        let distance = distanceFromBottom
        switch anchor {
        case .pinned where distance > EmberDesign.Stream.unpinDistance:
            anchor = .detached
            detachedWhileStreaming = isStreaming
        case .detached where distance <= Self.scrollSnap:
            anchor = .pinned
        default:
            break
        }
        updateJumpPill()
        scheduleTicksIfNeeded()
    }

    /// "Jump to latest" belongs to a live stream: it shows once the person has scrolled away while
    /// text was arriving, and stays (even after the stream ends) until they come back or use it.
    /// Scrolling up to reread a finished result shows nothing.
    private func updateJumpPill() {
        let show = anchor == .detached && detachedWhileStreaming
            && distanceFromBottom > EmberDesign.Stream.unpinDistance
        jumpPill.setShown(show, animated: window != nil)
    }

    private func updateEdgeMask() {
        let clipView = scrollView.contentView
        let fades = StreamEdgeMask.fades(documentHeight: documentHeight, clipHeight: clipView.bounds.height, offset: clipView.bounds.origin.y)
        // The clip view is flipped like its document: its layer reports no geometry flip, but
        // AppKit lays its sublayers (and this mask) out y-down, as the view's coordinates are.
        StreamEdgeMask.update(edgeMask, bounds: clipView.bounds, top: fades.top, bottom: fades.bottom, flipped: clipView.isFlipped)
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        isScrollingProgrammatically = true
        super.setFrameSize(newSize)
        isScrollingProgrammatically = false
        if newSize.height != oldSize.height {
            lastHeightChange = CACurrentMediaTime()
            if let heightCap, abs(newSize.height - heightCap) >= Self.scrollSnap {
                self.heightCap = nil
            }
        }
        if newSize.width != oldSize.width {
            updateTextContainerWidth()
        }
        updateLayoutDependents()
        scheduleTicksIfNeeded()
    }

    /// The text is laid out in the view's width minus the well's padding, and minus a legacy
    /// scroller's width (reserved whether or not the scroller shows), so the scroller appearing
    /// or disappearing never rewraps a line. An overlay scroller takes no width.
    private func updateTextContainerWidth() {
        guard let container = textView.textContainer else { return }
        let reserved = scrollView.scrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
        let width = max(bounds.width - reserved - textView.textContainerInset.width * 2, 0)
        guard container.size.width != width else { return }
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        isLayoutCurrent = false
        layOut()
        applyFades()
        reportContentHeightIfChanged(at: CACurrentMediaTime())
        updateCaretPosition()
    }

    @objc private func preferredScrollerStyleDidChange(_ notification: Notification) {
        // The scroll view adopts the new style first.
        DispatchQueue.main.async { [weak self] in
            self?.updateTextContainerWidth()
        }
    }

    override func layout() {
        super.layout()
        updateLayoutDependents()
    }

    private func updateLayoutDependents() {
        let size = jumpPill.fittingSize
        jumpPill.frame = NSRect(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: StreamLocalTokens.jumpPillBottomInset,
            width: size.width,
            height: size.height
        )
        updateCaretPosition()
        updateEdgeMask()
        updateJumpPill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ticker.stop()
        lastFrameTime = nil
        if window != nil {
            scheduleTicksIfNeeded()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        caret.setColor(for: effectiveAppearance)
        applyFades()
    }

    /// Offsets and heights closer than this count as equal (pixel rounding never lands exactly).
    private static let scrollSnap: CGFloat = 1
    /// A drain fires on the frame that comes within this fraction of the interval, so a 33 ms
    /// beat lands on every second 60 Hz frame and every fourth 120 Hz frame.
    private static let drainPhaseTolerance = 0.15
}
