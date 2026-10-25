import Testing
import UIKit
import PDFKit
@testable import SmartPrinterTechStack

@MainActor
struct PDFEditingTests {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID()).pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).writePDF(to: url) { context in
            for text in ["First", "Second", "Third"] {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
        let pdf = try #require(PDFDocument(url: url))
        let note = PDFAnnotation(bounds: CGRect(x: 70, y: 100, width: 60, height: 30), forType: .text, withProperties: nil)
        note.contents = "Keep this annotation"
        pdf.page(at: 0)?.addAnnotation(note)
        #expect(pdf.write(to: url))
        return url
    }

    @Test func reorderRotateDeletePreservesContentAndSource() throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let bytes = try Data(contentsOf: source)
        let output = try makeEditedPDF(source: source, pageIndices: [2, 0], rotations: [0: 90])
        defer { try? FileManager.default.removeItem(at: output) }
        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount == 2)
        #expect(pdf.page(at: 0)?.string?.contains("Third") == true)
        #expect(pdf.page(at: 1)?.string?.contains("First") == true)
        #expect(pdf.page(at: 1)?.rotation == 90)
        #expect(pdf.page(at: 1)?.annotations.contains { $0.contents == "Keep this annotation" } == true)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test func splitCropAndMergeRemainVectorAndKeepInputs() throws {
        let source = try fixture(), other = try fixture()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: other) }
        let bytes = try Data(contentsOf: source), otherBytes = try Data(contentsOf: other)
        let crop = CGRect(x: 20, y: 40, width: 240, height: 300)
        let output = try PDFEditing.write(source: source, pageIndices: [0], rotations: [0: 90], crops: [0: crop], appending: [other])
        defer { try? FileManager.default.removeItem(at: output) }
        let pdf = try #require(PDFDocument(url: output))
        #expect(pdf.pageCount == 4)
        #expect(pdf.page(at: 0)?.bounds(for: .cropBox) == crop)
        #expect(pdf.page(at: 0)?.rotation == 90)
        #expect(pdf.page(at: 0)?.annotations.first?.contents == "Keep this annotation")
        let cropped = try #require(pdf.page(at: 0))
        cropped.setBounds(cropped.bounds(for: .mediaBox), for: .cropBox)
        let restoredBytes = try #require(pdf.dataRepresentation())
        let restored = try #require(PDFDocument(data: restoredBytes))
        #expect(restored.page(at: 0)?.string?.contains("First") == true)
        #expect(pdf.page(at: 1)?.string?.contains("First") == true)
        #expect(pdf.page(at: 3)?.string?.contains("Third") == true)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try Data(contentsOf: other) == otherBytes)
    }

    @Test func rejectsInvalidPageListsAndCrops() throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        for indices in [[], [-1], [3], [0, 0]] {
            #expect(throws: (any Error).self) { try makeEditedPDF(source: source, pageIndices: indices, rotations: [:]) }
        }
        #expect(throws: (any Error).self) { try makeEditedPDF(source: source, pageIndices: [0], rotations: [0: 45]) }
        #expect(throws: (any Error).self) { try PDFEditing.write(source: source, pageIndices: [0], crops: [0: .zero]) }
        #expect(throws: (any Error).self) { try PDFEditing.write(source: source, pageIndices: [0], crops: [0: CGRect(x: -1, y: 0, width: 100, height: 100)]) }
        #expect(throws: (any Error).self) { try PDFEditing.write(source: source, pageIndices: [0], rotations: [2: 90]) }
    }

    @Test func rejectsLockedRestrictedAndSpoofedPDFs() throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let pdf = try #require(PDFDocument(url: source))
        for password in ["reader", ""] {
            let encrypted = FileManager.default.temporaryDirectory.appendingPathComponent("locked-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: encrypted) }
            #expect(pdf.write(to: encrypted, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: password, .accessPermissionsOption: 0]))
            #expect(throws: (any Error).self) { try makeEditedPDF(source: encrypted, pageIndices: [0], rotations: [:]) }
            #expect(throws: (any Error).self) { try PDFEditing.write(source: source, pageIndices: [0], appending: [encrypted]) }
        }
        let bad = source.deletingLastPathComponent().appendingPathComponent("bad-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: bad) }
        try Data("Not PDF".utf8).write(to: bad)
        #expect(throws: (any Error).self) { try makeEditedPDF(source: bad, pageIndices: [0], rotations: [:]) }
    }

    @Test func cancellationDoesNotChangeSource() async throws {
        let source = try fixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let bytes = try Data(contentsOf: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try makeEditedPDF(source: source, pageIndices: [0], rotations: [:])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: source) == bytes)
    }
}
