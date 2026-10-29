import Foundation

public enum SaveMode: Sendable { case overwrite, newCopy }

/// Kho file dùng chung cho danh sách, editor và dữ liệu mẫu.
@MainActor
public final class FileLibrary {
    public struct Item: Sendable {
        public let document: SourceDocument
        public let modifiedAt: Date
        public let byteCount: Int
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("Không tạo được kho file: \(error.localizedDescription)")
        }
    }

    public static func documents() -> FileLibrary {
        FileLibrary(folder: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrintFlow", isDirectory: true))
    }

    public func items() -> [Item] {
        do {
            let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
                .compactMap { url -> Item? in
                    guard let document = SourceDocument(url: url) else { return nil }
                    let values = try url.resourceValues(forKeys: keys)
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
                    return Item(document: document, modifiedAt: values.contentModificationDate ?? .distantPast,
                                byteCount: values.fileSize ?? 0)
                }
                .sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            print("Không đọc được kho file: \(error.localizedDescription)")
            return []
        }
    }

    public func importFile(at url: URL) throws -> SourceDocument {
        guard FileKind(url: url) != nil else { throw PrintFlowError.unsupported(url) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw PrintFlowError.unsupported(url) }
        let destination = uniqueURL(for: url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: destination)
        return SourceDocument(url: destination)!
    }

    public func save(_ data: Data, for original: SourceDocument, mode: SaveMode) throws -> SourceDocument {
        let destination: URL
        switch mode {
        case .overwrite: destination = original.url
        case .newCopy: destination = uniqueURL(for: original.url.lastPathComponent)
        }
        try data.write(to: destination, options: .atomic)
        return SourceDocument(url: destination)!
    }

    public func delete(_ document: SourceDocument) throws {
        try FileManager.default.removeItem(at: document.url)
    }

    /// Tên trùng được thêm hậu tố để không ghi đè file đã có.
    private func uniqueURL(for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(base) (\(n))"
            candidate = folder.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
            n += 1
        }
        return candidate
    }
}
