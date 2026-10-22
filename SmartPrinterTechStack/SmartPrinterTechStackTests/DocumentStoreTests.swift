import Foundation
import Testing
@testable import SmartPrinterTechStack

struct DocumentStoreTests {
    private func fixture() throws -> (URL, URL, DocumentStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.txt")
        try Data("original".utf8).write(to: source)
        return (directory, source, DocumentStore(rootURL: directory.appendingPathComponent("Library")))
    }

    @Test func duplicateNamesKeepIndependentDurableCopies() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await store.importFile(at: source, preferredName: "same.txt")
        try Data("second".utf8).write(to: source)
        let second = try await store.importFile(at: source, preferredName: "same.txt")
        try FileManager.default.removeItem(at: source)
        #expect(first.id != second.id)
        #expect(first.url != second.url)
        #expect(try Data(contentsOf: first.url) == Data("original".utf8))
        #expect(try Data(contentsOf: second.url) == Data("second".utf8))
        let reopened = DocumentStore(rootURL: directory.appendingPathComponent("Library"))
        #expect(try await reopened.list().count == 2)
    }

    @Test(arguments: ["../escape.txt", "a/b.txt", "a\\b.txt", "..", ".", "", "  ", ".hidden", "bad\u{0}name"])
    func renameRejectsUnsafeNames(name: String) async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try await store.importFile(at: source, preferredName: nil)
        await #expect(throws: (any Error).self) { try await store.rename(id: original.id, to: name) }
        #expect(try Data(contentsOf: original.url) == Data("original".utf8))
        #expect(try await store.list().first?.name == "source.txt")
    }

    @Test func missingSourceNeverPublishesDocument() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.removeItem(at: source)
        await #expect(throws: (any Error).self) { try await store.importFile(at: source, preferredName: nil) }
        #expect(try await store.list().isEmpty)
    }

    @Test func writeFailureNeverPublishesDocument() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("blocks staging directory".utf8).write(to: root.appendingPathComponent(".staging"))
        await #expect(throws: (any Error).self) { try await store.importFile(at: source, preferredName: nil) }
        #expect(try await store.list().isEmpty)
        #expect(try Data(contentsOf: source) == Data("original".utf8))
    }

    @Test func cancelledImportNeverPublishesDocument() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.importFile(at: source, preferredName: nil)
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(try await store.list().isEmpty)
        #expect(try Data(contentsOf: source) == Data("original".utf8))
    }

    @Test func publicationFailureRemovesStagedCopy() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let root = directory.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("occupied".utf8).write(to: root.appendingPathComponent(id.uuidString))
        await #expect(throws: (any Error).self) { try await store.importFile(at: source, preferredName: nil, id: id) }
        #expect(try await store.list().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".staging").path).isEmpty)
        #expect(try Data(contentsOf: source) == Data("original".utf8))
        #expect(try Data(contentsOf: root.appendingPathComponent(id.uuidString)) == Data("occupied".utf8))
    }

    @Test func incompleteStagingIsInvisible() async throws {
        let (directory, _, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let staged = directory.appendingPathComponent("Library/.staging/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: staged.appendingPathComponent("partial.txt"))
        #expect(try await store.list().isEmpty)
    }

    @Test func stableIDReturnsExistingCopyEvenWhenSourceExpired() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let first = try await store.importFile(at: source, preferredName: "first.txt", id: id)
        try FileManager.default.removeItem(at: source)
        let retry = try await store.importFile(at: source, preferredName: "other.txt", id: id)
        #expect(retry.url == first.url)
        #expect(try Data(contentsOf: retry.url) == Data("original".utf8))
        #expect(try await store.list().count == 1)
    }

    @Test func renameAndDeleteOnlyAffectSelectedCopy() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await store.importFile(at: source, preferredName: nil)
        let second = try await store.importFile(at: source, preferredName: nil)
        let renamed = try await store.rename(id: first.id, to: "Đã đổi tên.txt")
        #expect(renamed.id == first.id)
        #expect(renamed.name == "Đã đổi tên.txt")
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(try Data(contentsOf: renamed.url) == Data("original".utf8))
        try await store.delete(id: first.id)
        #expect(try await store.list().map(\.id) == [second.id])
        #expect(try Data(contentsOf: source) == Data("original".utf8))
    }

    @Test func directoriesAndSymbolicLinksAreRejected() async throws {
        let (directory, source, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        for url in [directory, link] {
            await #expect(throws: (any Error).self) { try await store.importFile(at: url, preferredName: nil) }
        }
        #expect(try await store.list().isEmpty)
    }
}
