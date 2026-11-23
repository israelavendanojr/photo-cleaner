import Foundation
import Testing
@testable import photo_swiper

/// Shared files live in `share-` folders in the temp directory (JUN-8), removed when the sheet closes and
/// swept at launch, so a crash mid-share never leaves a copy of a photo behind.
struct ShareFilesTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "sharefiles-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func eachShareGetsItsOwnFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try ShareFiles.makeFolder(in: root)
        let second = try ShareFiles.makeFolder(in: root)
        #expect(first != second)
        #expect(first.lastPathComponent.hasPrefix(ShareFiles.prefix))
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    @Test func removingAFileRemovesItsShareFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ShareFiles.makeFolder(in: root)
        let file = folder.appending(path: "IMG_0001.HEIC")
        try Data([1]).write(to: file)

        ShareFiles.remove(file)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: root.path), "Only the share folder")
    }

    @Test func removingAFileOutsideAShareFolderLeavesTheFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = root.appending(path: "plain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        let file = plain.appending(path: "a.jpg")
        try Data([1]).write(to: file)

        ShareFiles.remove(file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: plain.path))
    }

    @Test func theSweepTakesOnlyShareFiles() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ShareFiles.makeFolder(in: root)
        try Data([1]).write(to: folder.appending(path: "IMG_0001.MOV"))
        try Data([1]).write(to: root.appending(path: "share-stray.jpg"))
        let kept = ["edit-1.mov", "flatten-2.heic", "motion-3.mov", "preview-4.mov", "notes.txt"]
        for name in kept { try Data([1]).write(to: root.appending(path: name)) }

        ShareFiles.sweep(in: root)
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(left == kept.sorted())
    }

    @Test func sweepingAMissingFolderIsHarmless() {
        ShareFiles.sweep(in: FileManager.default.temporaryDirectory.appending(path: "nothing-\(UUID().uuidString)"))
    }
}
