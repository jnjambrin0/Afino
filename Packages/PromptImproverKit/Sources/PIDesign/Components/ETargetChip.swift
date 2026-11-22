import SwiftUI

/// The target selector chip in the panel footer: a 28 pt capsule with the
/// target's monogram tile, its name and an optional key cap ("Cl Claude ⇥").
/// `.fill.tertiary` (hover `.fill.secondary`), never glass. Changing `name`
/// crossfades the content over `Motion.targetChipCrossfade` (instant under
/// Reduce Motion). Dimming lowers its emphasis without disabling it.
///
/// ```swift
/// ETargetChip("Claude", monogram: .letters("Cl"), chord: KeyChord(.tab),
///             accessibilityLabel: "Target: Claude") { rotateTarget() }
/// ```
public struct ETargetChip: View {
    public let name: String
    public let monogram: EMonogram
    public var caps: [String]
    public var isDimmed: Bool
    public let accessibilityLabel: String
    public var accessibilityHint: String?
    public let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    /// - Parameters:
    ///   - accessibilityLabel: The full spoken name ("Target: Claude").
    ///   - accessibilityHint: What activating it does ("Changes the target").
    public init(
        _ name: String,
        monogram: EMonogram,
        chord: KeyChord? = nil,
        isDimmed: Bool = false,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            name,
            monogram: monogram,
            caps: chord.map(ShortcutGlyphFormatter.caps(for:)) ?? [],
            isDimmed: isDimmed,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: accessibilityHint,
            action: action
        )
    }

    public init(
        _ name: String,
        monogram: EMonogram,
        caps: [String],
        isDimmed: Bool = false,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.name = name
        self.monogram = monogram
        self.caps = caps
        self.isDimmed = isDimmed
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: EmberDesign.Chip.itemSpacing) {
                EMonogramTile(monogram)
                Text(verbatim: name)
                    .font(EmberDesign.Typography.chipName)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if !caps.isEmpty {
                    EKeyCapGroup(caps: caps)
                }
            }
            .foregroundStyle(.primary)
            .padding(.leading, EmberDesign.Chip.leadingInset)
            .padding(.trailing, caps.isEmpty ? EmberDesign.Chip.trailingPadding : EmberDesign.Chip.trailingCapPadding)
            .frame(minWidth: EmberDesign.Control.minimumHitTarget, minHeight: EmberDesign.Chip.targetHeight)
            .background(Capsule(style: .continuous).fill(EmberDesign.Materials.chipFill(isHovered: isHovered)))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .animation(reduceMotion ? nil : EmberDesign.Motion.targetChipCrossfade, value: name)
        .onHover { isHovered = isEnabled && $0 }
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .emberAccessibilityHint(accessibilityHint)
    }

    private var opacity: Double {
        if !isEnabled {
            return EmberDesign.Control.disabledOpacity
        }
        return isDimmed ? EmberDesign.Control.dimmedOpacity : 1
    }
}
