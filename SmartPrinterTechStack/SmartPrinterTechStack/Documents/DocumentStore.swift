import Foundation

actor DocumentStore {
    let rootURL: URL
    private let files = FileManager.default

    init(rootURL: URL) { self.rootURL = rootURL }

    func importFile(at url: URL, preferredName: String?, id: UUID = UUID()) throws -> LibraryDocument {
        if let existing = try document(id: id) { return existing }
        try Task.checkCancellation()
        let name = try validName(preferredName ?? url.lastPathComponent)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let staging = rootURL.appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        let output = staging.appendingPathComponent(name)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            do {
                try copyFile(from: coordinated, to: output)
            } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        try Task.checkCancellation()
        let finalDirectory = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        // Publishing the whole directory keeps partial copies out of the library.
        try files.moveItem(at: staging, to: finalDirectory)
        return LibraryDocument(id: id, url: finalDirectory.appendingPathComponent(name), name: name)
    }

    func list() throws -> [LibraryDocument] {
        guard files.fileExists(atPath: rootURL.path) else { return [] }
        return try files.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .compactMap { url in
                guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
                return try document(id: id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func rename(id: UUID, to name: String) throws -> LibraryDocument {
        let name = try validName(name)
        guard let original = try document(id: id) else { throw CocoaError(.fileNoSuchFile) }
        let destination = original.url.deletingLastPathComponent().appendingPathComponent(name)
        if destination != original.url { try files.moveItem(at: original.url, to: destination) }
        return LibraryDocument(id: id, url: destination, name: name)
    }

    func delete(id: UUID) throws {
        guard let original = try document(id: id) else { throw CocoaError(.fileNoSuchFile) }
        try files.removeItem(at: original.url.deletingLastPathComponent())
    }

    private func document(id: UUID) throws -> LibraryDocument? {
        let directory = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        guard files.fileExists(atPath: directory.path) else { return nil }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
        let contents = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard contents.count == 1, let url = contents.first else { return nil }
        let file = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard file.isRegularFile == true, file.isSymbolicLink != true else { return nil }
        return LibraryDocument(id: id, url: url, name: url.lastPathComponent)
    }

    private func validName(_ name: String) throws -> String {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return name
    }

    private func copyFile(from source: URL, to destination: URL) throws {
        var source = source
        source.removeAllCachedResourceValues()
        let metadata = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard files.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied = 0
        while true {
            try Task.checkCancellation()
            let chunk = try input.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
            copied += chunk.count
        }
        try output.synchronize()
        try output.close()
        guard copied == metadata.fileSize else { throw CocoaError(.fileReadCorruptFile) }
        let reopened = try FileHandle(forReadingFrom: destination)
        defer { try? reopened.close() }
        guard try reopened.seekToEnd() == UInt64(copied) else { throw CocoaError(.fileWriteUnknown) }
    }
}
