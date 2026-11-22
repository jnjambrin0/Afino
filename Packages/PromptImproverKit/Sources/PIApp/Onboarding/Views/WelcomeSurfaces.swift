import PIDesign
import SwiftUI

extension View {
    /// A raised card on the welcome's solid window: a quiet fill and a hairline. (`ECard` and the
    /// wells draw the window background colour, made for the panel's glass; on a solid window of
    /// that same colour they would not show.)
    func welcomeCard(radius: CGFloat = EmberDesign.Radius.large) -> some View {
        modifier(WelcomeCardSurface(radius: radius))
    }
}

private struct WelcomeCardSurface: ViewModifier {
    let radius: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(.fill.quinary))
            .overlay {
                shape.strokeBorder(
                    .separator.opacity(contrast == .increased ? 1 : EmberDesign.Card.hairlineOpacity),
                    lineWidth: contrast == .increased ? EmberDesign.Materials.wellStrokeWidth : EmberDesign.Control.hairlineWidth
                )
            }
    }
}
