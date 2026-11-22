import SwiftUI

/// One button of an `EDialog`.
public struct EDialogAction: Identifiable {
    public let id = UUID()
    public let title: String
    public var kind: EButtonStyle.Kind
    /// Return triggers it.
    public var isDefault: Bool
    /// Esc triggers it (unless it is also the default).
    public var isCancel: Bool
    public var isEnabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        kind: EButtonStyle.Kind = .secondary,
        isDefault: Bool = false,
        isCancel: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.isDefault = isDefault
        self.isCancel = isCancel
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// The Ember dialog: a glass card with a title, a message and buttons, shown
/// over a scrim by `emberDialog(isPresented:dialog:)`. The kit uses it instead
/// of `confirmationDialog`, `.alert` and `NSAlert`, so dialogs share the glass
/// and stay inside the window. Return and Esc map to the default and cancel
/// buttons.
public struct EDialog: View {
    public let title: String
    public var message: String?
    /// An SF Symbol before the title.
    public var symbol: String?
    /// The buttons, trailing-aligned in order.
    public let actions: [EDialogAction]
    public var accessibilityIdentifier: String?

    public init(
        _ title: String,
        message: String? = nil,
        symbol: String? = nil,
        actions: [EDialogAction],
        accessibilityIdentifier: String? = nil
    ) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.actions = actions
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EmberDesign.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: EmberDesign.Spacing.s) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(EmberDesign.Typography.dialogTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .font(EmberDesign.Typography.dialogTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let message {
                Text(verbatim: message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: EmberDesign.Spacing.s) {
                Spacer(minLength: 0)
                ForEach(actions) { action in
                    button(for: action)
                }
            }
            .padding(.top, EmberDesign.Spacing.xs)
        }
        .padding(EmberDesign.Card.padding + EmberDesign.Spacing.xs)
        .frame(width: EmberDesign.Card.dialogWidth, alignment: .leading)
        .emberFloatingCardSurface(cornerRadius: EmberDesign.Radius.large)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .emberAccessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func button(for action: EDialogAction) -> some View {
        let base = Button(action: action.action) {
            Text(verbatim: action.title)
        }
        .buttonStyle(.ember(action.kind))
        .disabled(!action.isEnabled)
        if action.isDefault {
            base.keyboardShortcut(.defaultAction)
        } else if action.isCancel {
            base.keyboardShortcut(.cancelAction)
        } else {
            base
        }
    }
}

public extension View {
    /// Shows `dialog` over this view with a scrim while `isPresented`.
    func emberDialog(isPresented: Bool, @ViewBuilder dialog: @escaping () -> EDialog) -> some View {
        modifier(EDialogHost(isPresented: isPresented, dialog: dialog))
    }
}

private struct EDialogHost: ViewModifier {
    let isPresented: Bool
    let dialog: () -> EDialog

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Rectangle()
                            .fill(EmberDesign.Glass.scrim)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        dialog()
                            .transition(EmberDesign.Motion.dialogTransition(reduceMotion: reduceMotion))
                    }
                }
            }
            .animation(EmberDesign.Motion.dialog(reduceMotion: reduceMotion), value: isPresented)
    }
}
