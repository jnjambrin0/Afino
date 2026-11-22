import CoreGraphics
@testable import PIApp
import Testing

/// Where the panel goes and how tall it may grow.
struct PanelPlacementTests {
    /// A 1440 × 900 display with a 25 pt menu bar.
    private let laptop = PanelScreenSnapshot(
        identifier: "laptop",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    /// A taller display to the right of it, with the Dock at the bottom.
    private let external = PanelScreenSnapshot(
        identifier: "external",
        frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1440, y: 80, width: 2560, height: 1335)
    )

    // MARK: Anchor

    @Test func theTopEdgeIs22PercentBelowTheTopOfTheVisibleFrame() {
        let anchor = PanelPlacement.anchor(on: laptop)

        #expect(anchor.top == 875 - (875 * 0.22).rounded())
        #expect(anchor.top == 682)
    }

    @Test func thePanelIs680WideAndCentred() {
        let anchor = PanelPlacement.anchor(on: external)

        #expect(anchor.width == 680)
        #expect(anchor.minX == CGFloat(1440 + (2560 - 680) / 2))
        let frame = anchor.frame(height: 96)
        #expect(frame.midX == external.visibleFrame.midX)
    }

    @Test func everyHeightKeepsTheTopEdgeWhereItIs() {
        let anchor = PanelPlacement.anchor(on: laptop)
        let heights: [CGFloat] = [96, 114, 274, 500]

        for height in heights {
            let frame = anchor.frame(height: height)
            #expect(frame.maxY == anchor.top)
            #expect(frame.height == min(height, anchor.maxHeight))
        }
    }

    @Test func theMaximumHeightLeavesTheBottomMargin() {
        // 875 − 193 − 24
        #expect(PanelPlacement.anchor(on: laptop).maxHeight == 658)
    }

    @Test func theMaximumHeightIsCappedAt720() {
        let anchor = PanelPlacement.anchor(on: external)

        #expect(anchor.maxHeight == 720)
        #expect(anchor.frame(height: 2000).height == 720)
    }

    @Test func aHeightAboveTheMaximumIsClampedAndTheTopStays() {
        let anchor = PanelPlacement.anchor(on: laptop)
        let frame = anchor.frame(height: 5000)

        #expect(frame.height == 658)
        #expect(frame.maxY == anchor.top)
        #expect(frame.minY == CGFloat(875 - 193 - 658))
        #expect(frame.minY == 24)
    }

    // MARK: Small screens

    @Test func onAShortScreenThePanelMovesUpToKeep420PointsOfRoom() {
        let short = PanelScreenSnapshot(
            identifier: "short",
            frame: CGRect(x: 0, y: 0, width: 1024, height: 525),
            visibleFrame: CGRect(x: 0, y: 0, width: 1024, height: 500)
        )
        let anchor = PanelPlacement.anchor(on: short)

        // 22 % would leave 500 − 110 − 24 = 366; the offset becomes 500 − 24 − 420 = 56.
        #expect(anchor.top == CGFloat(500 - 56))
        #expect(anchor.maxHeight == 420)
    }

    @Test func onAVeryShortScreenTheTopOffsetNeverGoesUnder24() {
        let tiny = PanelScreenSnapshot(
            identifier: "tiny",
            frame: CGRect(x: 0, y: 0, width: 800, height: 425),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 400)
        )
        let anchor = PanelPlacement.anchor(on: tiny)

        #expect(anchor.top == CGFloat(400 - 24))
        #expect(anchor.maxHeight == CGFloat(400 - 24 - 24))
    }

    @Test func aScreenWithEnoughRoomKeepsThe22PercentOffset() {
        let enough = PanelScreenSnapshot(
            identifier: "enough",
            frame: CGRect(x: 0, y: 0, width: 1280, height: 625),
            visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 600)
        )
        let anchor = PanelPlacement.anchor(on: enough)

        // 600 − 132 − 24 = 444 ≥ 420.
        #expect(anchor.top == CGFloat(600 - 132))
        #expect(anchor.maxHeight == 444)
    }

    @Test func aScreenNarrowerThanThePanelGetsAPanelAsWideAsItIs() {
        let narrow = PanelScreenSnapshot(
            identifier: "narrow",
            frame: CGRect(x: 0, y: 0, width: 600, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 875)
        )

        #expect(PanelPlacement.anchor(on: narrow).width == 600)
        #expect(PanelPlacement.anchor(on: narrow).minX == 0)
    }

    // MARK: Which screen

    @Test func theScreenUnderThePointerWins() {
        let target = PanelPlacement.resolveTargetScreen(
            mouseLocation: CGPoint(x: 2000, y: 700),
            currentScreenIdentifier: "laptop",
            screens: [laptop, external]
        )

        #expect(target == external)
    }

    @Test func thePanelOpensOnTheSecondScreenCentredThere() throws {
        let target = try #require(PanelPlacement.resolveTargetScreen(
            mouseLocation: CGPoint(x: 3000, y: 100),
            currentScreenIdentifier: nil,
            screens: [laptop, external]
        ))
        let frame = PanelPlacement.anchor(on: target).frame(height: 96)

        #expect(external.visibleFrame.contains(frame))
        #expect(frame.maxY == external.visibleFrame.maxY - (1335 * 0.22).rounded())
    }

    @Test func aPointerPushedAgainstTheTopEdgeStillCountsAsOnThatScreen() {
        let target = PanelPlacement.resolveTargetScreen(
            mouseLocation: CGPoint(x: 2000, y: 1440),
            currentScreenIdentifier: "laptop",
            screens: [laptop, external]
        )

        #expect(target == external)
    }

    @Test func onASharedEdgeTheScreenThatContainsThePointWins() {
        // x = 1440 is the external display's first column, not the laptop's last.
        let target = PanelPlacement.resolveTargetScreen(
            mouseLocation: CGPoint(x: 1440, y: 300),
            currentScreenIdentifier: nil,
            screens: [laptop, external]
        )

        #expect(target == external)
    }

    @Test func withThePointerOffEveryScreenThePanelsCurrentScreenWins() {
        let target = PanelPlacement.resolveTargetScreen(
            mouseLocation: CGPoint(x: -500, y: -500),
            currentScreenIdentifier: "external",
            screens: [laptop, external]
        )

        #expect(target == external)
    }

    @Test func otherwiseTheFirstScreenWins() {
        let target = PanelPlacement.resolveTargetScreen(
            mouseLocation: CGPoint(x: -500, y: -500),
            currentScreenIdentifier: "gone",
            screens: [laptop, external]
        )

        #expect(target == laptop)
        #expect(PanelPlacement.resolveTargetScreen(mouseLocation: .zero, currentScreenIdentifier: nil, screens: []) == nil)
    }
}
