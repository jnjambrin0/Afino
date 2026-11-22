import CoreGraphics
@testable import PIApp
import PIDesign
import Testing

/// The measures that keep Settings' edges in line.
struct SettingsLayoutTests {
    @Test
    func contentKeepsItsWidthWhenALegacyScrollerAppears() {
        let padding = EmberDesign.Settings.contentPadding
        #expect(SettingsLayout.trailingContentPadding(scrollerWidth: 0) == padding, "overlay scrollers take no room")
        // A 15 pt legacy scroller: the content gives back exactly what the scroller takes.
        #expect(SettingsLayout.trailingContentPadding(scrollerWidth: 15) + 15 == padding)
        // Never tighter than a small step, whatever the scroller.
        #expect(SettingsLayout.trailingContentPadding(scrollerWidth: 40) == EmberDesign.Spacing.s)
    }

    @Test
    func trailingControlsShareOneWidth() {
        #expect(SettingsLayout.selectMinWidth + EmberDesign.Control.horizontalPadding * 2 == SettingsLayout.trailingControlWidth)
        #expect(SettingsLayout.modelIDFieldWidth == SettingsLayout.trailingControlWidth)
        #expect(SettingsLayout.recorderWidth == SettingsLayout.trailingControlWidth)
    }
}

/// What VoiceOver reads for the API key field's link.
struct KeyFieldAccessibilityTests {
    @Test
    func linkTitlesAreSpokenWithoutTheArrow() {
        #expect(EKeyField.spokenLinkTitle("Get a key ↗") == "Get a key")
        #expect(EKeyField.spokenLinkTitle("Conseguir una clave ↗") == "Conseguir una clave")
        #expect(EKeyField.spokenLinkTitle("Plain") == "Plain")
    }
}
