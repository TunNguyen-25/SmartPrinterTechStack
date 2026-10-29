import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

/// Xử lý ảnh cho Image editor. Crop phối cảnh / filter scan có thể lấy từ DocumentScannerKit.
@MainActor
public final class ImageEditingService {
    private let context = CIContext()

    public init() {}

    public static func encode(_ image: UIImage, as type: UTType) throws -> Data {
        guard type.conforms(to: .image) else { throw PrintFlowError.cannotEncode }
        // Vẽ lại khi cần để lưu đúng hướng, kể cả ảnh chỉ có CIImage.
        let normalized: UIImage
        if image.imageOrientation != .up || image.cgImage == nil {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            normalized = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        } else {
            normalized = image
        }
        let data = NSMutableData()
        guard let cgImage = normalized.cgImage,
              let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw PrintFlowError.cannotEncode
        }
        let options: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PrintFlowError.cannotEncode }
        return data as Data
    }

    public func rotateRight(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    /// Ảnh đen trắng để in tiết kiệm mực.
    public func grayscale(_ image: UIImage) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let filter = CIFilter.photoEffectMono()
        filter.inputImage = input
        guard let output = filter.outputImage, let cgImage = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    // TODO: crop (TOCropViewController/Mantis), sáng/tương phản.
}
