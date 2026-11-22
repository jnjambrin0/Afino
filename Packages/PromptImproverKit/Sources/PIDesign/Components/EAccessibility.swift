import SwiftUI

extension View {
    /// Sets the accessibility identifier only when there is one.
    @ViewBuilder
    func emberAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    /// Sets the accessibility hint only when there is one.
    @ViewBuilder
    func emberAccessibilityHint(_ hint: String?) -> some View {
        if let hint {
            accessibilityHint(Text(verbatim: hint))
        } else {
            self
        }
    }
}
