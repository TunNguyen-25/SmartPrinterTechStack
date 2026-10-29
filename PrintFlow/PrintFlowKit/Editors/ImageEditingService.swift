import UIKit
import CoreImage.CIFilterBuiltins

/// Xử lý ảnh cho Image editor. Crop phối cảnh / filter scan có thể lấy từ DocumentScannerKit.
@MainActor
public final class ImageEditingService {
    private let context = CIContext()

    public init() {}

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
