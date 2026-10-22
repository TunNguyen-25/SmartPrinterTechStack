import UIKit
import QuickLookThumbnailing

actor DocumentThumbnailCache {
    static let shared = DocumentThumbnailCache()
    private let memory = NSCache<NSURL, UIImage>()
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DocumentThumbnails", isDirectory: true)

    init() {
        memory.countLimit = 60
        memory.totalCostLimit = 12 * 1_024 * 1_024
    }

    func summary(for document: LibraryDocument) async -> (detail: String, image: UIImage?) {
        let size: String
        do {
            let bytes = try document.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        } catch { size = "Không đọc được dung lượng" }
        let detail = "\(document.url.pathExtension.uppercased()) • \(size)"
        let key = directory.appendingPathComponent(document.id.uuidString + ".png")
        if let image = memory.object(forKey: key as NSURL) { return (detail, image) }
        if let image = UIImage(contentsOfFile: key.path) {
            memory.setObject(image, forKey: key as NSURL, cost: 160 * 160 * 4)
            return (detail, image)
        }
        let request = QLThumbnailGenerator.Request(fileAt: document.url, size: CGSize(width: 160, height: 160), scale: 1, representationTypes: .thumbnail)
        let image: UIImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { @Sendable thumbnail, _ in
                continuation.resume(returning: thumbnail?.uiImage)
            }
        }
        if let image {
            memory.setObject(image, forKey: key as NSURL, cost: 160 * 160 * 4)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let png = image.pngData() { try png.write(to: key, options: .atomic) }
                let cached = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                for old in cached.prefix(max(0, cached.count - 60)) { try FileManager.default.removeItem(at: old) }
            } catch { /* Cache is disposable; the document remains available. */ }
        }
        return (detail, image)
    }

    func remove(for id: UUID) {
        let key = directory.appendingPathComponent(id.uuidString + ".png")
        memory.removeObject(forKey: key as NSURL)
        try? FileManager.default.removeItem(at: key)
    }
}
