import Testing
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import SmartPrinterTechStack

@MainActor
struct ImageEditingTests {
    private func fixture(orientation: Int = 1, type: UTType = .png) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("image-\(UUID()).\(type.preferredFilenameExtension!)")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
            UIColor.blue.setFill(); context.fill(CGRect(x: 20, y: 30, width: 20, height: 30))
        }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
    private func decoded(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return bytes
    }
    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8]) func exportNormalizesEXIF(orientation: Int) async throws {
        let source = try fixture(orientation: orientation, type: .jpeg)
        defer { try? FileManager.default.removeItem(at: source) }
        let bytes = try Data(contentsOf: source)
        let output = try await ImageEditing.export(source: source, edits: ImageEdits())
        defer { try? FileManager.default.removeItem(at: output) }
        let image = try decoded(output)
        #expect(image.width == (orientation >= 5 ? 60 : 40))
        #expect(image.height == (orientation >= 5 ? 40 : 60))
        #expect(try Data(contentsOf: source) == bytes)
        let imageSource = try #require(CGImageSourceCreateWithURL(source as CFURL, nil))
        let expected = try #require(CGImageSourceCreateThumbnailAtIndex(imageSource, 0,
            [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 60] as CFDictionary))
        let actualPixel = try pixel(image, x: 5, y: 5), expectedPixel = try pixel(expected, x: 5, y: 5)
        for channel in 0..<3 { #expect(abs(Int(actualPixel[channel]) - Int(expectedPixel[channel])) < 15) }
    }
    @Test func cropAtEdgeResizeAndAlpha() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        var edits = ImageEdits()
        edits.crop = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        edits.size = CGSize(width: 10, height: 15)
        let output = try await ImageEditing.export(source: source, edits: edits)
        defer { try? FileManager.default.removeItem(at: output) }
        let image = try decoded(output)
        #expect(image.width == 10 && image.height == 15)
        let color = try pixel(image, x: 5, y: 7)
        #expect(color[2] > 240 && color[0] < 10)
        let alphaOutput = try await ImageEditing.export(source: source, edits: ImageEdits())
        defer { try? FileManager.default.removeItem(at: alphaOutput) }
        #expect(try pixel(decoded(alphaOutput), x: 30, y: 50)[3] == 0)
    }
    @Test func rotateAndFlipMovePixels() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        var edits = ImageEdits(); edits.quarterTurns = 1; edits.flipHorizontal = true
        let output = try await ImageEditing.export(source: source, edits: edits)
        defer { try? FileManager.default.removeItem(at: output) }
        let image = try decoded(output)
        #expect(image.width == 60 && image.height == 40)
        #expect(try pixel(image, x: 5, y: 35)[0] > 240)
    }
    @Test func grayscaleAndColorControls() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        var edits = ImageEdits(); edits.grayscale = true; edits.brightness = 0.1; edits.contrast = 1.2
        let output = try await ImageEditing.export(source: source, edits: edits)
        defer { try? FileManager.default.removeItem(at: output) }
        let color = try pixel(decoded(output), x: 5, y: 50)
        #expect(abs(Int(color[0]) - Int(color[1])) <= 1)
        #expect(abs(Int(color[1]) - Int(color[2])) <= 1)
        #expect(color[0] > 20 && color[3] == 255)
    }
    @Test func rejectsInvalidCropSizeAndUnsupportedContent() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        for crop in [CGRect.zero, CGRect(x: -0.1, y: 0, width: 1, height: 1), CGRect(x: 0.9, y: 0, width: 0.2, height: 1)] {
            var edits = ImageEdits(); edits.crop = crop
            await #expect(throws: (any Error).self) { try await ImageEditing.export(source: source, edits: edits) }
        }
        var edits = ImageEdits(); edits.size = CGSize(width: 0, height: 10)
        await #expect(throws: (any Error).self) { try await ImageEditing.export(source: source, edits: edits) }
        let bad = source.appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: bad) }
        try Data("Bad image".utf8).write(to: bad)
        await #expect(throws: (any Error).self) { try await ImageEditing.export(source: bad, edits: ImageEdits()) }
    }
    @Test func previewDownsamplesButExportUsesOriginalPixels() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let preview = try await ImageEditing.preview(source: source, edits: ImageEdits(), maxPixel: 20)
        #expect(preview.size == CGSize(width: 13, height: 20))
        let output = try await ImageEditing.export(source: source, edits: ImageEdits())
        defer { try? FileManager.default.removeItem(at: output) }
        #expect(try decoded(output).height == 60)
    }
    @Test func cancellationKeepsOriginal() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let bytes = try Data(contentsOf: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ImageEditing.export(source: source, edits: ImageEdits())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: source) == bytes)
    }
    @Test func verticalFlipAndBlackWhitePreserveTransparency() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        var edits = ImageEdits(); edits.flipVertical = true
        let flipped = try await ImageEditing.export(source: source, edits: edits)
        defer { try? FileManager.default.removeItem(at: flipped) }
        #expect(try pixel(decoded(flipped), x: 5, y: 5)[0] > 240)
        edits = ImageEdits(); edits.blackAndWhite = true
        let bw = try await ImageEditing.export(source: source, edits: edits)
        defer { try? FileManager.default.removeItem(at: bw) }
        let black = try pixel(decoded(bw), x: 5, y: 50)
        #expect(black[0] == 0 && black[1] == 0 && black[2] == 0 && black[3] == 255)
        #expect(try pixel(decoded(bw), x: 30, y: 50)[3] == 0)
    }

    @Test func heicDecodesAndExportsFromOriginal() async throws {
        let source = try fixture(orientation: 6, type: .heic)
        defer { try? FileManager.default.removeItem(at: source) }
        let bytes = try Data(contentsOf: source)
        let output = try await ImageEditing.export(source: source, edits: ImageEdits())
        defer { try? FileManager.default.removeItem(at: output) }
        let image = try decoded(output)
        #expect(image.width == 60 && image.height == 40)
        #expect(try Data(contentsOf: source) == bytes)
    }

}
