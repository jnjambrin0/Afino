import PIDesign

/// The panel's keyboard shortcuts as a readable list, for Settings › Shortcuts. Built from the
/// same table that drives the panel's keys, so the reference cannot drift from what the keys do.
struct ShortcutReferenceGroup: Identifiable, Equatable {
    struct Row: Identifiable, Equatable {
        let label: String
        let chord: KeyChord
        var id: String { label }
    }

    let title: String
    let rows: [Row]
    var id: String { title }
}
