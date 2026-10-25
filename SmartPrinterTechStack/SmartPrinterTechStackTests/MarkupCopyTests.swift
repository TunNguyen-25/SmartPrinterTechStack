import Testing
import UIKit
import QuickLook
@testable import SmartPrinterTechStack

@MainActor
struct MarkupCopyTests {
    @Test func callbackCapturesTemporaryCopyBeforeItExpiresAndPersistsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.png")
        let edited = root.appendingPathComponent("callback.png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        }
        let bytes = try #require(image.pngData())
        try bytes.write(to: original); try bytes.write(to: edited)
        let store = DocumentStore(rootURL: root.appendingPathComponent("library"))
        let input = try await store.importFile(at: original, preferredName: nil)
        let controller = DocumentPreviewViewController(document: input, store: store)
        let ql = QLPreviewController()
        #expect(controller.previewController(ql, editingModeFor: input.url as NSURL) == .createCopy)
        controller.previewController(ql, didSaveEditedCopyOf: input.url as NSURL, at: edited)
        try FileManager.default.removeItem(at: edited)
        let task = try #require(controller.markupImportTask)
        let saved = try await task.value
        #expect(saved.id != input.id)
        #expect(saved.name == "original-markup.png")
        #expect(try Data(contentsOf: saved.url) == bytes)
        #expect(try Data(contentsOf: input.url) == bytes)
        #expect(try await store.list().count == 2)
    }

    @Test func cancelDoesNotCreateOutputAndOfficeCannotEdit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentStore(rootURL: root)
        let document = LibraryDocument(id: UUID(), url: root.appendingPathComponent("office.docx"), name: "office.docx")
        let controller = DocumentPreviewViewController(document: document, store: store)
        let ql = QLPreviewController()
        #expect(controller.previewController(ql, editingModeFor: document.url as NSURL) == .disabled)
        controller.previewControllerDidDismiss(ql)
        #expect(controller.markupImportTask == nil)
        #expect(try await store.list().isEmpty)
    }
    @Test func callbackDetectsContentWithNoExtensionAndRejectsCorruptOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("photo.jpg")
        let temporary = root.appendingPathComponent("callback-without-extension")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20)).image { _ in UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 10, height: 20)) }
        try #require(image.pngData()).write(to: original)
        try #require(image.pngData()).write(to: temporary)
        let store = DocumentStore(rootURL: root.appendingPathComponent("library"))
        let input = try await store.importFile(at: original, preferredName: nil)
        let controller = DocumentPreviewViewController(document: input, store: store)
        let ql = QLPreviewController()
        controller.previewController(ql, didSaveEditedCopyOf: input.url as NSURL, at: temporary)
        let saving = try #require(controller.markupImportTask)
        let output = try await saving.value
        #expect(output.name == "photo-markup.png")
        try Data("Not an edited image".utf8).write(to: temporary)
        controller.previewController(ql, didSaveEditedCopyOf: input.url as NSURL, at: temporary)
        let invalid = try #require(controller.markupImportTask)
        await #expect(throws: (any Error).self) { try await invalid.value }
        #expect(try await store.list().count == 2)
    }

    @Test func failedMarkupImportDoesNotOverwriteOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("photo.png"), badRoot = root.appendingPathComponent("not-a-directory")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20)).image { _ in UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 10, height: 20)) }
        let bytes = try #require(image.pngData()); try bytes.write(to: original)
        try Data("file".utf8).write(to: badRoot)
        let store = DocumentStore(rootURL: badRoot)
        let input = LibraryDocument(id: UUID(), url: original, name: "photo.png")
        let controller = DocumentPreviewViewController(document: input, store: store)
        controller.previewController(QLPreviewController(), didSaveEditedCopyOf: original as NSURL, at: original)
        let saving = try #require(controller.markupImportTask)
        await #expect(throws: (any Error).self) { try await saving.value }
        #expect(try Data(contentsOf: original) == bytes)
    }

}
