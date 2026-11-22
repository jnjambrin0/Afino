/// A typed setting: its `UserDefaults` key and the value it has until the user changes it.
///
/// Keys are declared next to their owner (`extension ConfigKey where Value == Bool { static let … }`),
/// not in a central registry.
public struct ConfigKey<Value: ConfigValue>: Sendable {
    /// The `UserDefaults` key.
    public let name: String
    /// The value the setting has while nothing is stored for it.
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}
