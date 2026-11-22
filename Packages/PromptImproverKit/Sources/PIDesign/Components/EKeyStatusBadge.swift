import SwiftUI

/// The state of an API key in Settings and the no-key card.
public enum EKeyStatus: Hashable, Sendable, CaseIterable {
    /// No key stored.
    case notSet
    /// Validating with the provider.
    case checking
    /// The provider accepted it.
    case valid
    /// The provider rejected it.
    case invalid
    /// Stored but not checked (offline, rate limited).
    case unverified

    /// The SF Symbol shown for the state (`checking` shows a spinner).
    public var symbol: String {
        switch self {
        case .notSet: "circle.dashed"
        case .checking: "ellipsis.circle"
        case .valid: "checkmark.circle.fill"
        case .invalid: "xmark.circle.fill"
        case .unverified: "exclamationmark.circle.fill"
        }
    }

    /// The glyph's status tint.
    public var tint: Color {
        switch self {
        case .notSet, .checking: EmberDesign.Status.neutral
        case .valid: EmberDesign.Status.positive
        case .invalid: EmberDesign.Status.negative
        case .unverified: EmberDesign.Status.caution
        }
    }
}

/// A key status as a word, a glyph and a tint: state is never shown by colour
/// alone. The caller supplies the localized word.
///
/// ```swift
/// EKeyStatusBadge(.valid, title: "Valid")
/// ```
public struct EKeyStatusBadge: View {
    public let status: EKeyStatus
    public let title: String

    public init(_ status: EKeyStatus, title: String) {
        self.status = status
        self.title = title
    }

    public var body: some View {
        HStack(spacing: EmberDesign.Badge.glyphSpacing) {
            Group {
                if status == .checking {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.tint)
                }
            }
            .accessibilityHidden(true)
            Text(verbatim: title)
                .foregroundStyle(status == .notSet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .font(EmberDesign.Typography.badge)
        .lineLimit(1)
        .padding(.horizontal, EmberDesign.Badge.horizontalPadding)
        .padding(.vertical, EmberDesign.Badge.verticalPadding)
        .background(Capsule(style: .continuous).fill(.fill.tertiary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
    }
}
