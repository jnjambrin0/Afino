import Foundation

/// Where the tool writes and asks; tests substitute a scripted one.
protocol EvalConsole: Sendable {
    func write(_ line: String)
    func writeError(_ line: String)
    /// One line typed by the person, or nil at the end of input.
    func readLine() -> String?
}

/// The terminal: unbuffered standard output and error.
struct StandardConsole: EvalConsole {
    func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    func writeError(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    func readLine() -> String? {
        Swift.readLine(strippingNewline: true)
    }
}
