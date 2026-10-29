import Foundation
import UniformTypeIdentifiers

/// Loại file quyết định mở editor nào. Sau editor, mọi loại đều thành PDF.
public enum FileKind: Sendable {
    case pdf, image, text

    public init?(url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .pdf) { self = .pdf }
        else if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .plainText) { self = .text }
        else { return nil }
    }
}

public struct SourceDocument: Sendable {
    public let url: URL
    public let kind: FileKind

    /// nil khi định dạng chưa hỗ trợ.
    public init?(url: URL) {
        guard let kind = FileKind(url: url) else { return nil }
        self.url = url
        self.kind = kind
    }

    public var name: String { url.deletingPathExtension().lastPathComponent }
}

public enum PrintFlowError: LocalizedError {
    case empty
    case unreadable(URL)
    case unsupported(URL)

    public var errorDescription: String? {
        switch self {
        case .empty: "Chưa chọn tài liệu để in."
        case .unreadable(let url): "Không đọc được file \(url.lastPathComponent)."
        case .unsupported(let url): "Chưa hỗ trợ file \(url.lastPathComponent)."
        }
    }
}
