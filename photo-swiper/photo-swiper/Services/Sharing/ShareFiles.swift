import Foundation
import OSLog
import UniformTypeIdentifiers

/// Where shared files live while the share sheet is up (JUN-8): one `share-<UUID>` folder per share in the
/// temp directory, holding the file under its original name, so the recipient sees `IMG_1234.HEIC` and not
/// an id. The view model removes the folder when the sheet closes; the launch sweep catches any a crash
/// left behind, so no copy of a photo lingers on disk.
enum ShareFiles {
    static let prefix = "share-"

    /// A new, empty share folder.
    static func makeFolder(in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = directory.appending(path: "\(prefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// `file`'s name in its share folder: the original's name with the extension of what was exported,
    /// or "Photo" / "Video" when the original's name isn't known.
    static func fileName(original: String?, type: UTType?, fallback: String) -> String {
        let stem = original.map { ($0 as NSString).deletingPathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        let suffix = type?.preferredFilenameExtension ?? original.map { ($0 as NSString).pathExtension } ?? ""
        return suffix.isEmpty ? stem : "\(stem).\(suffix)"
    }

    /// Removes a prepared file and, when it's in a share folder, the folder with it.
    static func remove(_ file: URL) {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: folder.lastPathComponent.hasPrefix(prefix) ? folder : file)
    }

    /// Removes every `share-` file and folder directly in `directory`. Run once at launch, before any share.
    static func sweep(in directory: URL = FileManager.default.temporaryDirectory) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let stale = names.filter { $0.hasPrefix(prefix) }
        for name in stale { try? FileManager.default.removeItem(at: directory.appending(path: name)) }
        if !stale.isEmpty { log.info("Swept \(stale.count) stale share files") }
    }

    private static let log = Logger.app(category: "share")
}
