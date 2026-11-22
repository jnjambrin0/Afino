import CoreGraphics
import Testing
@testable import PIDesign

struct FloatingPlacementTests {
    let container = CGSize(width: 680, height: 400)
    let card = CGSize(width: 264, height: 120)
    let margin = EmberDesign.Card.edgeMargin

    @Test
    func attachedCardOpensBelowItsControl() {
        let button = CGRect(x: 100, y: 40, width: 120, height: 28)
        let placement = EFloatingPlacement.origin(for: card, attachedTo: button, in: container)
        #expect(placement.isAbove == false)
        #expect(placement.origin == CGPoint(x: 100, y: button.maxY + EmberDesign.Card.anchorGap))
    }

    @Test
    func attachedCardFlipsAboveWithoutCoveringItsControl() {
        let button = CGRect(x: 100, y: 320, width: 120, height: 28)
        let placement = EFloatingPlacement.origin(for: card, attachedTo: button, in: container)
        #expect(placement.isAbove)
        #expect(placement.origin.y + card.height <= button.minY)
    }

    @Test
    func attachedCardHonorsPreferAboveOnlyWithRoom() {
        let low = CGRect(x: 100, y: 300, width: 120, height: 28)
        #expect(EFloatingPlacement.origin(for: card, attachedTo: low, in: container, preferAbove: true).isAbove)
        let high = CGRect(x: 100, y: 20, width: 120, height: 28)
        #expect(EFloatingPlacement.origin(for: card, attachedTo: high, in: container, preferAbove: true).isAbove == false)
    }

    @Test
    func attachedCardIsClampedHorizontally() {
        let button = CGRect(x: 600, y: 40, width: 60, height: 28)
        let placement = EFloatingPlacement.origin(for: card, attachedTo: button, in: container)
        #expect(placement.origin.x == container.width - card.width - margin)
    }

    @Test
    func aClickIsTheCardsOnlyInsideAnOpenCard() {
        let cards = [CGRect(x: 100, y: 40, width: 200, height: 150), CGRect(x: 400, y: 40, width: 100, height: 60)]
        #expect(EFloatingPlacement.contains(CGPoint(x: 150, y: 100), in: cards))
        #expect(EFloatingPlacement.contains(CGPoint(x: 450, y: 50), in: cards))
        #expect(!EFloatingPlacement.contains(CGPoint(x: 350, y: 100), in: cards), "between the cards is outside")
        #expect(!EFloatingPlacement.contains(CGPoint(x: 150, y: 20), in: cards), "the select button above the card is outside")
        #expect(!EFloatingPlacement.contains(CGPoint(x: 10, y: 10), in: []), "no card: every click is outside")
    }
}
