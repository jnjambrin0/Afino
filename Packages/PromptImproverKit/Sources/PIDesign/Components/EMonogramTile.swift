import SwiftUI

/// A monochrome identity mark: two letters ("Cl", "Gp") or an SF Symbol
/// ("circle.dotted"). Never a third-party logo.
public enum EMonogram: Hashable, Sendable {
    /// Up to two letters, drawn as text.
    case letters(String)
    /// An SF Symbol name.
    case symbol(String)
}

/// An 18 × 18 pt tile (radius 5, `.fill.tertiary`) with a monogram. Decorative:
/// the control it sits in carries the name. The glyph inherits the
/// surrounding foreground style (primary, or the selection foreground on a
/// highlighted menu row).
public struct EMonogramTile: View {
    public let monogram: EMonogram

    public init(_ monogram: EMonogram) {
        self.monogram = monogram
    }

    public init(letters: String) {
        self.init(.letters(letters))
    }

    public init(symbol: String) {
        self.init(.symbol(symbol))
    }

    public var body: some View {
        glyph
            .font(EmberDesign.Typography.monogram)
            .lineLimit(1)
            .minimumScaleFactor(EmberDesign.Chip.monogramMinimumScale)
            .frame(width: EmberDesign.Chip.monogramSize, height: EmberDesign.Chip.monogramSize)
            .background(
                RoundedRectangle(cornerRadius: EmberDesign.Radius.monogram, style: .continuous)
                    .fill(.fill.tertiary)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch monogram {
        case .letters(let letters):
            Text(verbatim: letters)
        case .symbol(let name):
            Image(systemName: name)
                .imageScale(.small)
        }
    }
}
