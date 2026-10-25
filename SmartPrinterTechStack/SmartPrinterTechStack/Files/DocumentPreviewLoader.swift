import UIKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

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
    @concurrent static func editedCopyExtension(at url: URL) async throws -> String {
        try Task.checkCancellation()
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let identifier = CGImageSourceGetType(source) {
            guard [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier].contains(identifier as String),
                  CGImageSourceGetCount(source) == 1,
                  CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) != nil,
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  let ext = UTType(identifier as String)?.preferredFilenameExtension else { throw ImageEditing.Failure.unsupported }
            return ext
        }
        _ = try PDFEditing.open(url)
        return "pdf"
    }

}
