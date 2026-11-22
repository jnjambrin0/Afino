import CoreGraphics
@testable import PIApp
import PIDesign
import Testing

/// How tall the panel is in each state.
struct PanelHeightTests {
    private func height(_ screen: PanelScreen, configure: (inout PanelHeightInput) -> Void = { _ in }) -> CGFloat {
        var input = PanelHeightInput(screen: screen)
        configure(&input)
        return PanelPresentation.height(input)
    }

    // MARK: Compose = 32 + 20n + 44

    @Test(arguments: 1...10)
    func composeIs32Plus20PerLinePlusTheFooter(lines: Int) {
        let input = EmberDesign.Panel.inputHeight(forLines: lines)
        #expect(input == 32 + 20 * CGFloat(lines))
        #expect(height(.compose) { $0.inputHeight = input } == 32 + 20 * CGFloat(lines) + 44)
    }

    @Test func oneLineOfComposeIs96() {
        #expect(height(.compose) == 96)
        #expect(height(.compose) == EmberDesign.Panel.composeHeight)
    }

    // MARK: Running, result, failed, stopped = 40 + well + 44 (+ 36)

    @Test(arguments: [PanelScreen.running, .result, .failed, .stopped])
    func theWellNeverStartsUnderThreeLines(screen: PanelScreen) {
        #expect(height(screen) == CGFloat(40 + 91 + 44))
        #expect(height(screen) { $0.contentHeight = 60 } == 175)
    }

    @Test func theWellGrowsWithItsText() {
        #expect(height(.result) { $0.contentHeight = 300 } == CGFloat(40 + 300 + 44))
        // Fractional heights round up so the last line is never clipped.
        #expect(height(.result) { $0.contentHeight = 300.2 } == CGFloat(40 + 301 + 44))
    }

    @Test func aNoticeRowAdds36() {
        #expect(height(.stopped) { $0.showsNotice = true } == CGFloat(40 + 91 + 36 + 44))
        #expect(height(.failed) {
            $0.contentHeight = 200
            $0.showsNotice = true
        } == CGFloat(40 + 200 + 36 + 44))
    }

    @Test func theWellStopsAtWhatTheScreenLeaves() {
        // A 1440 × 900 laptop: max height 658.
        #expect(height(.result) {
            $0.contentHeight = 2000
            $0.maxHeight = 658
        } == 658)
        let input = PanelHeightInput(screen: .result, contentHeight: 2000, showsNotice: true, maxHeight: 658)
        #expect(PanelPresentation.wellHeight(input) == CGFloat(658 - 84 - 36))
        #expect(PanelPresentation.height(input) == 658)
        #expect(height(.result) { $0.contentHeight = 5000 } == 720)
    }

    @Test func anExpandedOriginalTakesItsMeasuredHeight() {
        #expect(height(.result) { $0.headerHeight = 120 } == CGFloat(120 + 91 + 44))
        let input = PanelHeightInput(screen: .result, headerHeight: 120, contentHeight: 2000, maxHeight: 658)
        #expect(PanelPresentation.wellHeight(input) == CGFloat(658 - 120 - 44))
    }

    @Test func onATinyScreenNothingIsTallerThanTheRoomThereIs() {
        #expect(height(.result) { $0.maxHeight = 150 } == 150)
        #expect(height(.setup) { $0.maxHeight = 150 } == 150)
    }

    // MARK: Cards

    @Test func theKeyCardIs232() {
        #expect(height(.setup) == 232)
    }

    @Test func theHistoryShowsUpToEightRowsAndRoomForItsEmptyState() {
        // 52 filter + rows × 42 + 2 × 4 + 44 footer.
        #expect(height(.history) { $0.historyRows = 0 } == CGFloat(52 + 3 * 42 + 8 + 44))
        #expect(height(.history) { $0.historyRows = 1 } == CGFloat(52 + 42 + 8 + 44))
        #expect(height(.history) { $0.historyRows = 5 } == CGFloat(52 + 5 * 42 + 8 + 44))
        #expect(height(.history) { $0.historyRows = 8 } == CGFloat(52 + 8 * 42 + 8 + 44))
        #expect(height(.history) { $0.historyRows = 50 } == CGFloat(52 + 8 * 42 + 8 + 44))
    }
}
