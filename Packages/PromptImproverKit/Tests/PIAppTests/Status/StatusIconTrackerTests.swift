import AppKit
@testable import PIApp
import PICore
import PIProviders
import Testing

/// The menu bar icon, derived from the session's phases, the panel's visibility and the key.
struct StatusIconTrackerTests {
    private static let running = SessionState.Phase.running(.writing)
    private static let failure = SessionState.Phase.failed(.engine(.offline, provider: .anthropic, requestID: nil))

    @Test func atRestTheIconIsIdle() {
        let tracker = StatusIconTracker()
        #expect(tracker.state(phase: .composing, hasUsableKey: true) == .idle)
        #expect(tracker.state(phase: .result, hasUsableKey: true) == .idle)
    }

    @Test(arguments: [SessionState.RunStage.connecting, .thinking, .writing, .retrying(.overloaded)])
    func aRunInFlightBreathesWhateverItsStage(stage: SessionState.RunStage) {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: .composing, to: .running(stage), isPanelVisible: false)
        #expect(tracker.state(phase: .running(stage), hasUsableKey: true) == .running)
        // Even without a key: the run is what matters while it lasts.
        #expect(tracker.state(phase: .running(stage), hasUsableKey: false) == .running)
    }

    @Test func aRunFinishedWithThePanelHiddenShowsTheCheckUntilItsTimeIsUp() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: .composing, to: Self.running, isPanelVisible: false)

        let startsTimer = tracker.phaseChanged(from: Self.running, to: .result, isPanelVisible: false)

        #expect(startsTimer)
        #expect(tracker.state(phase: .result, hasUsableKey: true) == .done)
        tracker.doneExpired()
        #expect(tracker.state(phase: .result, hasUsableKey: true) == .idle)
    }

    @Test func aRunFinishedInFrontOfTheUserShowsNoCheck() {
        var tracker = StatusIconTracker()
        let startsTimer = tracker.phaseChanged(from: Self.running, to: .result, isPanelVisible: true)
        #expect(!startsTimer)
        #expect(tracker.state(phase: .result, hasUsableKey: true) == .idle)
    }

    @Test func aRunFailedWithThePanelHiddenNeedsAttentionUntilThePanelOpens() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: Self.running, to: Self.failure, isPanelVisible: false)
        #expect(tracker.state(phase: Self.failure, hasUsableKey: true) == .attention(.runFailed))

        // Still there later, whatever else happens to the session.
        tracker.phaseChanged(from: Self.failure, to: Self.failure, isPanelVisible: false)
        #expect(tracker.state(phase: Self.failure, hasUsableKey: true) == .attention(.runFailed))

        tracker.panelDidOpen()
        #expect(tracker.state(phase: Self.failure, hasUsableKey: true) == .idle)
    }

    @Test func aFailureInFrontOfTheUserNeedsNoAttention() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: Self.running, to: Self.failure, isPanelVisible: true)
        #expect(tracker.state(phase: Self.failure, hasUsableKey: true) == .idle)
    }

    @Test func stoppingIsNotAFailure() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: Self.running, to: .stopped, isPanelVisible: false)
        #expect(tracker.state(phase: .stopped, hasUsableKey: true) == .idle)
    }

    @Test func aTruncatedResultIsAFailure() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: Self.running, to: .failed(.truncated), isPanelVisible: false)
        #expect(tracker.state(phase: .failed(.truncated), hasUsableKey: true) == .attention(.runFailed))
    }

    @Test func withoutAUsableKeyTheIconAsksForOne() {
        let tracker = StatusIconTracker()
        #expect(tracker.state(phase: .composing, hasUsableKey: false) == .attention(.noUsableKey))
    }

    @Test func aNewRunTakesTheCheckAway() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: Self.running, to: .result, isPanelVisible: false)
        tracker.phaseChanged(from: .result, to: Self.running, isPanelVisible: false)
        #expect(tracker.state(phase: Self.running, hasUsableKey: true) == .running)
        tracker.phaseChanged(from: Self.running, to: .stopped, isPanelVisible: false)
        #expect(tracker.state(phase: .stopped, hasUsableKey: true) == .idle)
    }

    @Test func aCompletedRunClearsAnEarlierFailure() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: Self.running, to: Self.failure, isPanelVisible: false)
        tracker.phaseChanged(from: Self.failure, to: Self.running, isPanelVisible: false)
        tracker.phaseChanged(from: Self.running, to: .result, isPanelVisible: false)
        #expect(tracker.state(phase: .result, hasUsableKey: true) == .done)
        tracker.doneExpired()
        #expect(tracker.state(phase: .result, hasUsableKey: true) == .idle)
    }

    @Test func openingThePanelTakesTheCheckAway() {
        var tracker = StatusIconTracker()
        tracker.phaseChanged(from: Self.running, to: .result, isPanelVisible: false)
        tracker.panelDidOpen()
        #expect(tracker.state(phase: .result, hasUsableKey: true) == .idle)
    }

    @Test func eachStateIsDrawnAsDesigned() {
        #expect(StatusIconAppearance(.idle, reduceMotion: false) == .init(glyph: .cursor, hasDot: false, breathes: false))
        #expect(StatusIconAppearance(.running, reduceMotion: false) == .init(glyph: .cursor, hasDot: false, breathes: true))
        // Reduce Motion: a dot instead of breathing.
        #expect(StatusIconAppearance(.running, reduceMotion: true) == .init(glyph: .cursor, hasDot: true, breathes: false))
        #expect(StatusIconAppearance(.done, reduceMotion: false) == .init(glyph: .checkmark, hasDot: false, breathes: false))
        #expect(StatusIconAppearance(.attention(.runFailed), reduceMotion: false) == .init(glyph: .cursor, hasDot: true, breathes: false))
        #expect(StatusIconAppearance(.attention(.noUsableKey), reduceMotion: true) == .init(glyph: .cursor, hasDot: true, breathes: false))
    }

    @Test func everyStateHasAnImage() {
        for state in [StatusIconState.idle, .running, .done, .attention(.runFailed)] {
            for reduceMotion in [false, true] {
                let appearance = StatusIconAppearance(state, reduceMotion: reduceMotion)
                let image = StatusIconRenderer.image(for: appearance, accessibilityDescription: "x")
                #expect(image?.isTemplate == true)
                if appearance.hasDot || appearance.glyph == .checkmark {
                    // Composed images keep the glyph's canvas, so the item never changes width.
                    #expect(image?.size == StatusIconRenderer.Metrics.iconSize)
                }
            }
        }
    }

    @Test func composedIconsFillTheirCanvasAtEveryScale() throws {
        let image = try #require(StatusIconRenderer.image(
            for: StatusIconAppearance(glyph: .cursor, hasDot: true, breathes: false),
            accessibilityDescription: "x"
        ))
        let representations = image.representations.compactMap { $0 as? NSBitmapImageRep }
        #expect(representations.map(\.pixelsHigh).sorted() == [18, 36])
        for representation in representations {
            // The glyph reaches the top third: it spans the canvas instead of one corner of it.
            let topThird = 0..<(representation.pixelsHigh / 3)
            let hasInk = topThird.contains { y in
                (0..<representation.pixelsWide).contains { x in
                    (representation.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5
                }
            }
            #expect(hasInk, "nothing drawn in the top third at \(representation.pixelsHigh) px")
        }
    }
}
