import AppKit

/// The well's scroll view. It tells its owner when the person scrolls with a mouse wheel or
/// trackpad, as opposed to scrolling the owner does itself. (A scroller drag reaches the owner
/// through the clip view's bounds notifications instead.)
final class StreamScrollView: NSScrollView {
    /// Called after every scroll-wheel event, once the content has moved.
    var onUserScroll: (() -> Void)?

    /// True while a trackpad gesture or its momentum is under way.
    private(set) var isUserInteracting = false

    override func scrollWheel(with event: NSEvent) {
        let active: NSEvent.Phase = [.began, .changed, .mayBegin, .stationary]
        isUserInteracting = !event.phase.isDisjoint(with: active) || !event.momentumPhase.isDisjoint(with: active)
        super.scrollWheel(with: event)
        onUserScroll?()
    }
}
