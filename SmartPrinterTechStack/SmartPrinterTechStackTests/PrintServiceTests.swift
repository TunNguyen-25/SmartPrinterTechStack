import UIKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import SmartPrinterTechStack

@MainActor
struct PrintServiceTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func document(_ url: URL) -> LibraryDocument {
        LibraryDocument(id: UUID(), url: url, name: url.lastPathComponent)
    }
    private func pdf(at url: URL) throws {
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).writePDF(to: url) { context in
            for text in ["First page", "Second page"] {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
    }
    private func image(at url: URL, color: UIColor) throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        try #require(image.pngData()).write(to: url)
    }

    @Test func preparesPDFSnapshotWithoutChangingSource() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("input.pdf")
        try pdf(at: source)
        let bytes = try Data(contentsOf: source)
        let output = try await PrintPreparation.prepare(document: document(source))
        defer { try? FileManager.default.removeItem(at: output) }
        #expect(output != source)
        #expect(try Data(contentsOf: output) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        let prepared = try #require(PDFDocument(url: output))
        #expect(prepared.pageCount == 2)
        #expect(prepared.page(at: 1)?.string?.contains("Second page") == true)
    }

    @Test func preparesImageAsPrintablePDF() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("image.png")
        try image(at: source, color: .red)
        let bytes = try Data(contentsOf: source)
        let output = try await PrintPreparation.prepare(document: document(source))
        defer { try? FileManager.default.removeItem(at: output) }
        #expect(PDFDocument(url: output)?.pageCount == 1)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func rejectsCorruptSpoofedAndUnsupportedInput() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["bad.pdf", "bad.png", "office.docx", "missing.pdf"] {
            let source = dir.appendingPathComponent(name)
            if name != "missing.pdf" { try Data("not a document".utf8).write(to: source) }
            await #expect(throws: (any Error).self) { try await PrintPreparation.prepare(document: document(source)) }
        }
        let disguised = dir.appendingPathComponent("image.pdf")
        try image(at: disguised, color: .red)
        await #expect(throws: (any Error).self) { try await PrintPreparation.prepare(document: document(disguised)) }
    }

    @Test func rejectsLockedAndPrintingForbiddenPDFs() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.pdf")
        try pdf(at: source)
        let pdf = try #require(PDFDocument(url: source))
        let locked = dir.appendingPathComponent("locked.pdf")
        #expect(pdf.write(to: locked, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "reader"]))
        #expect(PDFDocument(url: locked)?.isLocked == true)
        await #expect(throws: PrintPreparation.Failure.locked) { try await PrintPreparation.prepare(document: document(locked)) }
        let forbidden = dir.appendingPathComponent("no-print.pdf")
        #expect(pdf.write(to: forbidden, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "", .accessPermissionsOption: NSNumber(value: 0)]))
        #expect(PDFDocument(url: forbidden)?.allowsPrinting == false)
        let bytes = try Data(contentsOf: forbidden)
        await #expect(throws: PrintPreparation.Failure.printingDenied) { try await PrintPreparation.prepare(document: document(forbidden)) }
        #expect(try Data(contentsOf: forbidden) == bytes)
    }

    @Test func imagePDFPreservesSelectionOrder() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let red = dir.appendingPathComponent("z.png"), blue = dir.appendingPathComponent("a.png")
        try image(at: red, color: .red)
        try image(at: blue, color: .blue)
        let output = try await PrintPreparation.imagesPDF(at: [red, blue, red])
        defer { try? FileManager.default.removeItem(at: output) }
        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount == 3)
        for (index, expected) in [0, 2, 0].enumerated() {
            let page = try #require(pdf.page(at: index))
            let thumbnail = page.thumbnail(of: CGSize(width: 20, height: 20), for: .mediaBox)
            let cgImage = try #require(thumbnail.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: -10, y: -10, width: 20, height: 20))
            #expect(pixel[expected] > 200)
            #expect(pixel[expected == 0 ? 2 : 0] < 50)
        }
    }

    @Test func imagePDFHonorsEXIFOrientation() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("oriented.jpg")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let destination = try #require(CGImageDestinationCreateWithURL(input as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let output = try await PrintPreparation.imagesPDF(at: [input])
        defer { try? FileManager.default.removeItem(at: output) }
        let page = try #require(PDFDocument(url: output)?.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        #expect(bounds.width > bounds.height)
    }

    @Test func cancelledAndInvalidImageBatchesFailWithoutChangingInputs() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("image.png")
        try image(at: source, color: .green)
        let bytes = try Data(contentsOf: source)
        await #expect(throws: (any Error).self) { try await PrintPreparation.imagesPDF(at: []) }
        await #expect(throws: (any Error).self) { try await PrintPreparation.imagesPDF(at: [source, dir.appendingPathComponent("missing.png")]) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PrintPreparation.imagesPDF(at: [source])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test(arguments: [PrintPaperSize.a4, .letter]) func calibrationHasCorrectPaperAndRuler(paper: PrintPaperSize) async throws {
        let output = try await PrintPreparation.calibration(paper: paper)
        defer { try? FileManager.default.removeItem(at: output) }
        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount == 1)
        let page = try #require(pdf.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let width = paper == .a4 ? 595.2756 : 612.0
        let height = paper == .a4 ? 841.8898 : 792.0
        #expect(abs(bounds.width - width) < 0.01)
        #expect(abs(bounds.height - height) < 0.01)
        #expect(page.string?.contains("100 mm") == true)
        #expect(page.string?.contains(paper.rawValue) == true)
    }
}
