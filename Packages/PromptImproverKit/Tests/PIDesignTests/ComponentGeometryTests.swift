import AppKit
import SwiftUI
import Testing
@testable import PIDesign

/// Interactive components keep a 28 × 28 pt hit target; fixed-size pieces
/// (tiles, caps, the target chip) render at their token sizes.
struct ComponentGeometryTests {
    private func size(of view: some View) -> CGSize {
        let host = NSHostingView(rootView: view)
        return host.fittingSize
    }

    private func meetsHitTarget(_ size: CGSize) -> Bool {
        size.width >= EmberDesign.Control.minimumHitTarget && size.height >= EmberDesign.Control.minimumHitTarget
    }

    @Test
    func buttonsKeepTheHitTarget() {
        for kind in [EButtonStyle.Kind.primary, .secondary, .ghost, .destructive] {
            #expect(meetsHitTarget(size(of: Button("A") {}.buttonStyle(.ember(kind)))))
            #expect(meetsHitTarget(size(of: Button("A") {}.buttonStyle(.ember(kind, size: .small)))))
        }
        let icon = size(of: Button("Copy", systemImage: "doc.on.doc") {}.labelStyle(.iconOnly).buttonStyle(.emberIcon))
        #expect(icon == CGSize(width: 28, height: 28))
    }

    @Test
    func controlsKeepTheHitTarget() {
        #expect(meetsHitTarget(size(of: Toggle("On", isOn: .constant(true)).toggleStyle(.ember).labelsHidden())))
        #expect(meetsHitTarget(size(of: EChoiceChips("Theme", options: ["A"], selection: .constant("A")))))
        #expect(meetsHitTarget(size(of: ESelect("Pick", options: [1, 2], selection: .constant(1)) { "\($0)" })))
        #expect(meetsHitTarget(size(of: EField("Key", text: .constant("")))))
        #expect(meetsHitTarget(size(of: EChoiceChips("Provider", options: ["A", "B"], selection: .constant("A"), isAvailable: { $0 == "A" }) { $0 })))
        #expect(meetsHitTarget(size(of: EActionChip("Add", symbol: "plus") {})))
    }

    @Test
    func aRowsControlsLineUp() {
        let field = size(of: EField("Key", text: .constant("")))
        let button = size(of: Button("Paste") {}.buttonStyle(.ember(.secondary)))
        let select = size(of: ESelect("Pick", options: [1, 2], selection: .constant(1)) { "\($0)" })
        #expect(field.height == button.height)
        #expect(select.height == button.height)
    }

    @Test
    func switchDrawsItsTrackInsideTheHitTarget() {
        let toggle = size(of: Toggle("On", isOn: .constant(false)).toggleStyle(.ember).labelsHidden())
        #expect(toggle.width == max(EmberDesign.Control.switchSize.width, EmberDesign.Control.minimumHitTarget))
        #expect(toggle.height == EmberDesign.Control.minimumHitTarget)
    }

    @Test
    func targetChipIsATwentyEightPointCapsule() {
        let chip = size(of: ETargetChip("Claude", monogram: .letters("Cl"), chord: KeyChord(.tab), accessibilityLabel: "Target: Claude") {})
        #expect(chip.height == EmberDesign.Chip.targetHeight)
        #expect(chip.width > chip.height)
    }

    @Test
    func monogramTileIsEighteenPointsSquare() {
        #expect(size(of: EMonogramTile(letters: "Gp")) == CGSize(width: 18, height: 18))
        #expect(size(of: EMonogramTile(symbol: "circle.dotted")) == CGSize(width: 18, height: 18))
    }

    @Test
    func keyCapsAreEighteenPointsTall() {
        #expect(size(of: EKeyCap(glyph: "⌘")).height == EmberDesign.KeyCap.height)
        #expect(size(of: EKeyCap(glyph: "⌘")).width == EmberDesign.KeyCap.minWidth)
        let group = size(of: EKeyCapGroup(KeyChord(.char("k"), .command)))
        #expect(group.width == EmberDesign.KeyCap.minWidth * 2 + EmberDesign.KeyCap.capSpacing)
    }

    @Test
    func keyStatusBadgesRenderEveryState() {
        for status in EKeyStatus.allCases {
            let badge = size(of: EKeyStatusBadge(status, title: "Word"))
            #expect(badge.width > 0 && badge.height > 0)
        }
        #expect(Set(EKeyStatus.allCases.map(\.symbol)).count == EKeyStatus.allCases.count, "each state has its own glyph")
    }

    @Test
    func menuCardRendersCheckedAndMonogramRows() {
        let card = EMenuCard(
            items: [
                EMenuItem(id: "a", title: "Claude", monogram: .letters("Cl"), isChecked: true),
                EMenuItem(id: "b", title: "GPT", monogram: .letters("Gp"), section: 1),
            ],
            highlightedID: "b",
            onHover: { _ in },
            onSelect: { _ in }
        )
        let fitted = size(of: card)
        #expect(fitted.width == EmberDesign.Card.menuWidth)
        #expect(fitted.height >= EmberDesign.Card.menuRowHeight * 2)
    }
}
