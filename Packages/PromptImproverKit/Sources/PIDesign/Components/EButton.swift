import SwiftUI

// Ember buttons. Custom chrome, native semantics: these are `ButtonStyle`s, so
// the button keeps its role, `keyboardShortcut`, Full Keyboard Access focus and
// VoiceOver behaviour.

/// Text buttons.
///
/// - `primary`: `Brand.onAccent` on the accent fill, for the one action that moves forward
///   (Return). **One primary per surface.**
/// - `secondary`: a quiet fill.
/// - `ghost`: no fill until hovered.
/// - `destructive`: red text on a faint red fill.
///
/// Usage: `Button("Improve") { … }.buttonStyle(.ember(.primary))`.
public struct EButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        case primary
        case secondary
        case ghost
        case destructive
    }

    public enum Size: Sendable {
        /// 28 pt tall.
        case regular
        /// 24 pt tall, with the same 28 pt hit target.
        case small
    }

    public var kind: Kind
    public var size: Size

    public init(kind: Kind = .secondary, size: Size = .regular) {
        self.kind = kind
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        EButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

public extension ButtonStyle where Self == EButtonStyle {
    /// An Ember text button: `.buttonStyle(.ember(.primary))`.
    static func ember(_ kind: EButtonStyle.Kind = .secondary, size: EButtonStyle.Size = .regular) -> EButtonStyle {
        EButtonStyle(kind: kind, size: size)
    }
}

private struct EButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: EButtonStyle.Kind
    let size: EButtonStyle.Size

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    /// Every text button is a capsule: at 24–28 pt that is the macOS 26 large-control shape,
    /// and it sits concentric with the panel's corners and with the chips and selects beside it.
    private var shape: Capsule {
        Capsule(style: .continuous)
    }

    private var isPressed: Bool {
        configuration.isPressed && isEnabled
    }

    var body: some View {
        configuration.label
            .font(size == .regular ? EmberDesign.Typography.button : EmberDesign.Typography.buttonSmall)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, size == .regular ? EmberDesign.Control.horizontalPadding : EmberDesign.Control.smallHorizontalPadding)
            .frame(minHeight: size == .regular ? EmberDesign.Control.height : EmberDesign.Control.smallHeight)
            .background(shape.fill(fill))
            .overlay {
                if showsContrastStroke {
                    shape.strokeBorder(.separator, lineWidth: EmberDesign.Control.hairlineWidth)
                }
            }
            // A solid fill darkens; a translucent one steps up the fill scale instead, because
            // brightness cannot darken a translucent fill visibly on light backgrounds.
            .brightness(isPressed && kind == .primary ? EmberDesign.Control.pressedBrightness : 0)
            // The keyboard focus ring follows the capsule, not the hit target.
            .contentShape(.focusEffect, shape)
            // Small buttons draw at 24 pt but keep a 28 pt hit target.
            .frame(minWidth: EmberDesign.Control.minimumHitTarget, minHeight: EmberDesign.Control.minimumHitTarget)
            .contentShape(.interaction, Rectangle())
            .opacity(isEnabled ? 1 : EmberDesign.Control.disabledOpacity)
            .environment(\.emberKeyCapBackdrop, kind == .primary ? .accent : .plain)
            .onHover { isHovered = isEnabled && $0 }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { isHovered = false }
            }
    }

    private var showsContrastStroke: Bool {
        contrast == .increased && (kind == .secondary || (kind == .ghost && (isHovered || isPressed)))
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .primary:
            AnyShapeStyle(EmberDesign.Brand.accent)
        case .secondary:
            EmberDesign.Materials.quietFill(isHovered: isHovered, isPressed: isPressed)
        case .ghost:
            isPressed || isHovered
                ? EmberDesign.Materials.quietFill(isHovered: isHovered, isPressed: isPressed)
                : AnyShapeStyle(.clear)
        case .destructive:
            AnyShapeStyle(EmberDesign.Status.negative.opacity(destructiveOpacity))
        }
    }

    private var destructiveOpacity: Double {
        if isPressed { return EmberDesign.Control.destructivePressedFillOpacity }
        return isHovered ? EmberDesign.Control.destructiveHoverFillOpacity : EmberDesign.Control.destructiveFillOpacity
    }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .primary:
            AnyShapeStyle(EmberDesign.Brand.onAccent)
        case .secondary:
            AnyShapeStyle(.primary)
        case .ghost:
            isHovered || isPressed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        case .destructive:
            AnyShapeStyle(EmberDesign.Status.negative)
        }
    }
}

/// A button label with an optional symbol and its shortcut: "Improve ↩".
/// The caps adapt to the button's fill.
public struct EButtonLabel: View {
    public let title: String
    public var systemImage: String?
    public var caps: [String]

    public init(_ title: String, systemImage: String? = nil, chord: KeyChord? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.caps = chord.map(ShortcutGlyphFormatter.caps(for:)) ?? []
    }

    /// For shortcuts that aren't a `KeyChord` (a recorded global shortcut).
    public init(_ title: String, systemImage: String? = nil, caps: [String]) {
        self.title = title
        self.systemImage = systemImage
        self.caps = caps
    }

    public var body: some View {
        HStack(spacing: EmberDesign.Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(verbatim: title)
            if !caps.isEmpty {
                EKeyCapGroup(caps: caps)
            }
        }
    }
}

/// Square icon buttons for chrome (header, footer, Settings rows). Quiet until
/// hovered; `isActive` keeps the hover fill (a toggled state). Give the button
/// an accessibility label: `Button("History", systemImage: "clock") { … }
/// .labelStyle(.iconOnly).buttonStyle(.emberIcon)`.
public struct EIconButtonStyle: ButtonStyle {
    public var size: CGFloat
    public var isActive: Bool

    public init(size: CGFloat = EmberDesign.Control.iconButtonSize, isActive: Bool = false) {
        self.size = size
        self.isActive = isActive
    }

    public func makeBody(configuration: Configuration) -> some View {
        EIconButtonBody(configuration: configuration, size: size, isActive: isActive)
    }
}

public extension ButtonStyle where Self == EIconButtonStyle {
    /// A round icon button: `.buttonStyle(.emberIcon)`.
    static var emberIcon: EIconButtonStyle { EIconButtonStyle() }

    /// A round icon button that keeps its hover fill while `isActive` (a toggled state).
    static func emberIcon(isActive: Bool) -> EIconButtonStyle {
        EIconButtonStyle(isActive: isActive)
    }
}

private struct EIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    /// Round, like the system's toolbar and inline icon buttons.
    private var shape: Circle {
        Circle()
    }

    private var isPressed: Bool {
        configuration.isPressed && isEnabled
    }

    var body: some View {
        configuration.label
            .font(EmberDesign.Typography.chromeGlyph)
            .foregroundStyle(isHovered || isActive || isPressed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: size, height: size)
            .background(shape.fill(background))
            .frame(minWidth: EmberDesign.Control.minimumHitTarget, minHeight: EmberDesign.Control.minimumHitTarget)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : EmberDesign.Control.disabledOpacity)
            .onHover { isHovered = isEnabled && $0 }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { isHovered = false }
            }
    }

    private var background: AnyShapeStyle {
        guard isHovered || isActive || isPressed else { return AnyShapeStyle(.clear) }
        return EmberDesign.Materials.quietFill(isHovered: isHovered || isActive, isPressed: isPressed)
    }
}
