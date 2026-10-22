import Foundation
import ImageIO
import PDFKit
import Testing
import UIKit
@testable import SmartPrinterTechStack

struct DocumentPreviewTests {
    @Test func offlinePDFReopensWithOnePage() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let url = try #require(bundle.url(forResource: "Sample", withExtension: "pdf"))
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
        #expect(document.string?.contains("Smart Printer Lab") == true)
    }

    @Test func imagePreviewDownsamplesAndAppliesEXIFOrientation() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 4096, height: 2048, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let preview = try await DocumentPreviewLoader.image(at: url)
        #expect(preview.cgImage?.width == 1024)
        #expect(preview.cgImage?.height == 2048)
    }

    @Test func invalidImageCannotReportPreviewSuccess() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await DocumentPreviewLoader.image(at: url) }
    }
}
