import UIKit
import ImageIO
import PDFKit

nonisolated enum DocumentPreviewLoader {
    @concurrent static func image(at url: URL) async throws -> UIImage {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()
        return UIImage(cgImage: image)
    }

    @concurrent static func pdf(at url: URL) async throws -> sending PDFDocument {
        try Task.checkCancellation()
        guard let pdf = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        return pdf
    }
}
