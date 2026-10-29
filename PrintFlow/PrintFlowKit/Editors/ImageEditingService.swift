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
        let data = NSMutableData()
        guard let cgImage = upright(image).cgImage,
              let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw PrintFlowError.cannotEncode
        }
        let options: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PrintFlowError.cannotEncode }
        return data as Data
    }

    /// Vẽ lại ảnh camera (orientation != .up) hoặc ảnh chỉ có CIImage để crop/xoay không bị lệch.
    public static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up || image.cgImage == nil else { return image }
        return render(image.size, scale: image.scale) { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }

    /// Bản nhỏ (cạnh dài ≤ `maxPixels`) để preview slider cho mượt.
    public func downsampled(_ image: UIImage, maxPixels: CGFloat = 1200) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = maxPixels / max(pixels.width, pixels.height)
        guard ratio < 1 else { return image }
        let size = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
        return Self.render(size, scale: 1) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    public func rotateRight(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        return Self.render(size, scale: image.scale) { context in
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    public func flipHorizontal(_ image: UIImage) -> UIImage {
        Self.render(image.size, scale: image.scale) { context in
            context.cgContext.translateBy(x: image.size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// `normalizedRect` trong 0…1, toạ độ ảnh đã chuẩn hoá orientation (gốc trên-trái).
    public func crop(_ image: UIImage, to normalizedRect: CGRect) -> UIImage {
        guard let cgImage = Self.upright(image).cgImage else { return image }
        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        let rect = CGRect(x: normalizedRect.minX * width, y: normalizedRect.minY * height,
                          width: normalizedRect.width * width, height: normalizedRect.height * height)
            .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1, let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    /// CIColorControls: brightness -0.5…0.5, contrast 0.5…1.5.
    public func adjust(_ image: UIImage, brightness: Float, contrast: Float) -> UIImage {
        guard let input = CIImage(image: Self.upright(image)) else { return image }
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.brightness = brightness
        filter.contrast = contrast
        return output(filter.outputImage, extent: input.extent, scale: image.scale) ?? image
    }

    /// Ảnh đen trắng để in tiết kiệm mực.
    public func grayscale(_ image: UIImage) -> UIImage {
        guard let input = CIImage(image: Self.upright(image)) else { return image }
        let filter = CIFilter.photoEffectMono()
        filter.inputImage = input
        return output(filter.outputImage, extent: input.extent, scale: image.scale) ?? image
    }

    private func output(_ ciImage: CIImage?, extent: CGRect, scale: CGFloat) -> UIImage? {
        guard let ciImage, let cgImage = context.createCGImage(ciImage, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Giữ đúng scale của ảnh gốc, nếu không renderer dùng scale màn hình và làm phình số pixel.
    private static func render(_ size: CGSize, scale: CGFloat, actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: actions)
    }
}
