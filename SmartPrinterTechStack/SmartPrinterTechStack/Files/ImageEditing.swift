import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ImageEdits: Sendable {
    // Crop uses normalized top-left coordinates after orientation, rotation and flips.
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var quarterTurns = 0
    var flipHorizontal = false
    var flipVertical = false
    var size: CGSize?
    var grayscale = false
    var blackAndWhite = false
    var brightness = 0.0
    var contrast = 1.0
}

nonisolated enum ImageEditing {
    enum Failure: Error, LocalizedError {
        case unsupported, invalidEdits
        var errorDescription: String? {
            switch self {
            case .unsupported: "Chỉ sửa ảnh tĩnh JPEG/PNG/HEIC có nội dung hợp lệ."
            case .invalidEdits: "Crop phải nằm trong ảnh; kích thước phải là số pixel nguyên dương. Brightness: -1…1; contrast: 0…4."
            }
        }
    }
    private static func imageSource(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source),
              [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier].contains(type as String),
              CGImageSourceGetCount(source) == 1 else { throw Failure.unsupported }
        return source
    }
    private static func edited(_ source: CIImage, edits: ImageEdits) throws -> CIImage {
        let crop = edits.crop
        guard crop.origin.x.isFinite, crop.origin.y.isFinite, crop.width.isFinite, crop.height.isFinite,
              crop.width > 0, crop.height > 0, CGRect(x: 0, y: 0, width: 1, height: 1).contains(crop),
              edits.brightness.isFinite, (-1...1).contains(edits.brightness),
              edits.contrast.isFinite, (0...4).contains(edits.contrast) else { throw Failure.invalidEdits }
        var image = source
        let turns = (edits.quarterTurns % 4 + 4) % 4
        if turns != 0 { image = image.oriented(forExifOrientation: [1, 6, 3, 8][turns]) }
        if edits.flipHorizontal { image = image.oriented(forExifOrientation: 2) }
        if edits.flipVertical { image = image.oriented(forExifOrientation: 4) }
        let extent = image.extent
        let area = CGRect(x: extent.minX + crop.minX * extent.width, y: extent.minY + (1 - crop.maxY) * extent.height,
                          width: crop.width * extent.width, height: crop.height * extent.height).integral.intersection(extent)
        guard area.width >= 1, area.height >= 1 else { throw Failure.invalidEdits }
        image = image.cropped(to: area).transformed(by: CGAffineTransform(translationX: -area.minX, y: -area.minY))
        if let size = edits.size {
            guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
                  size.width.rounded() == size.width, size.height.rounded() == size.height else { throw Failure.invalidEdits }
            image = image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width, y: size.height / image.extent.height))
        }
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: edits.grayscale || edits.blackAndWhite ? 0 : 1,
            kCIInputBrightnessKey: edits.brightness, kCIInputContrastKey: edits.contrast
        ])
        if edits.blackAndWhite { image = image.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.5]) }
        return image
    }

    @concurrent static func export(source: URL, edits: ImageEdits) async throws -> URL {
        try Task.checkCancellation()
        _ = try imageSource(source)
        guard let input = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]) else { throw Failure.unsupported }
        let image = try edited(input, edits: edits)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("edited-\(UUID()).png")
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: output) } }
        let context = CIContext(options: [.cacheIntermediates: false])
        try Task.checkCancellation()
        try context.writePNGRepresentation(of: image, to: output, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        try Task.checkCancellation()
        let reopened = try imageSource(output)
        guard CGImageSourceGetStatus(reopened) == .statusComplete else { throw Failure.unsupported }
        complete = true
        return output
    }

    @concurrent static func preview(source: URL, edits: ImageEdits, maxPixel: Int = 1600) async throws -> UIImage {
        try Task.checkCancellation()
        guard maxPixel > 0 else { throw Failure.invalidEdits }
        let source = try imageSource(source)
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw Failure.unsupported }
        var image = try edited(CIImage(cgImage: thumbnail), edits: edits)
        let scale = min(1, CGFloat(maxPixel) / max(image.extent.width, image.extent.height))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        try Task.checkCancellation()
        guard let cg = CIContext(options: [.cacheIntermediates: false]).createCGImage(image, from: image.extent) else { throw Failure.unsupported }
        return UIImage(cgImage: cg)
    }
}
