import Foundation
import UniformTypeIdentifiers

/// Loại file quyết định mở editor; chỉ chuyển sang PDF khi xem trước in.
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
    case cannotEncode
    case empty
    case unreadable(URL)
    case unsupported(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotEncode: "Không mã hoá được tài liệu theo định dạng gốc."
        case .empty: "Chưa chọn tài liệu để in."
        case .unreadable(let url): "Không đọc được file \(url.lastPathComponent)."
        case .unsupported(let url): "Chưa hỗ trợ file \(url.lastPathComponent)."
        }
    }
}
