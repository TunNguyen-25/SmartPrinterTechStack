import UIKit
import PDFKit

/// Các tech stack sửa PDF đang thử. Editor tự dismiss; `onSave` nhận file PDF mới trong thư mục tạm.
public enum PDFEditorEngine: String, CaseIterable, Sendable {
    case quickLook = "Quick Look markup"
    case pdfKit = "PDFKit + PencilKit"
    case paperKit = "PaperKit (iOS 26+)"

    public var isAvailable: Bool {
        guard self == .paperKit else { return true }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// nil khi engine không có trên OS này hoặc PDF không mở được / bị khóa.
    @MainActor public func makeViewController(url: URL, onSave: @escaping @MainActor (URL) -> Void) -> UIViewController? {
        if self == .quickLook { return QuickLookMarkupController(url: url, onSave: onSave) }
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { return nil }
        let editor: UIViewController
        switch self {
        case .quickLook: return nil
        case .pdfKit: editor = PDFAnnotateViewController(document: document, onSave: onSave)
        case .paperKit:
            guard #available(iOS 26.0, *) else { return nil }
            editor = PaperKitPDFViewController(document: document, onSave: onSave)
        }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .fullScreen
        return nav
    }
}

nonisolated func temporaryPDFURL(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString).pdf")
}
