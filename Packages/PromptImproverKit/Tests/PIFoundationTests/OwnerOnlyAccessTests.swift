import Foundation
import PIFoundation
import Testing

struct OwnerOnlyAccessTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "AfinoAccessTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func permissions(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func write(_ name: String, in folder: URL, mode: Int) throws -> URL {
        let file = folder.appending(path: name)
        try Data("history".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path)
        return file
    }

    @Test func aFolderAndEverythingInItBecomeTheUsersAlone() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "com.jnjambrin0.PromptImprover", directoryHint: .isDirectory)
        let external = folder.appending(path: "Legacy-0.x/guides", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        let history = try write("history.json", in: folder, mode: 0o644)
        let guide = try write("imported.md", in: external, mode: 0o644)
        let alreadyPrivate = try write("history.corrupt-20261121-120000.json", in: folder, mode: 0o600)

        let changed = try OwnerOnlyAccess.restrict(folder)

        #expect(try permissions(of: folder) == 0o700)
        #expect(try permissions(of: external) == 0o700)
        #expect(try permissions(of: external.deletingLastPathComponent()) == 0o700)
        #expect(try permissions(of: history) == 0o600)
        #expect(try permissions(of: guide) == 0o600)
        #expect(try permissions(of: alreadyPrivate) == 0o600)
        // Three folders and two files changed; the third file already had its mode.
        #expect(changed == 5)
        #expect(try OwnerOnlyAccess.restrict(folder) == 0)
    }

    @Test func aMissingFolderIsCreatedForTheUserAlone() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "new/com.jnjambrin0.PromptImprover", directoryHint: .isDirectory)

        try OwnerOnlyAccess.restrict(folder)

        #expect(try permissions(of: folder) == 0o700)
    }

    @Test func symbolicLinksAreNeitherFollowedNorChanged() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "com.jnjambrin0.PromptImprover", directoryHint: .isDirectory)
        let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let outside = try write("outside.txt", in: elsewhere, mode: 0o644)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "link"), withDestinationURL: elsewhere)

        try OwnerOnlyAccess.restrict(folder)

        #expect(try permissions(of: outside) == 0o644)
    }
}
