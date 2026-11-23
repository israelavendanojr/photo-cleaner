#if DEBUG
import UIKit

/// Shares the mock library's items for real, so `-mockLibrary YES` can open the share sheet in the
/// simulator: a short wait (long enough to see the spinner and cancel it), then a mock photo as JPEG
/// without location, or the sample clip every mock video plays.
struct MockMediaSharer: MediaSharing {
    var duration: Duration = .seconds(1)

    func prepare(_ item: LibraryItem) async throws -> URL {
        let steps = 5
        for _ in 1...steps { try await Task.sleep(for: duration / steps) }

        guard case .bundled(let name) = item.image else { throw ShareError.gone }
        let folder = try ShareFiles.makeFolder()
        do {
            if item.isVideo {
                guard let clip = Bundle.main.url(forResource: "mock-video", withExtension: "mp4") else { throw ShareError.exportFailed }
                let url = folder.appending(path: "\(name).mp4")
                try FileManager.default.copyItem(at: clip, to: url)
                return url
            }
            guard let data = UIImage(named: name)?.jpegData(compressionQuality: 0.95) else { throw ShareError.exportFailed }
            let url = folder.appending(path: "\(name).jpg")
            try ShareMetadata.strippingLocation(imageData: data).write(to: url)
            return url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw (error as? ShareError) ?? .exportFailed
        }
    }
}
#endif
