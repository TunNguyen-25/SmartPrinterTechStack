import UIKit
import PDFKit

/// Composition root: giữ service dùng chung và là nơi duy nhất `new` các màn hình.
/// Muốn thay service (mock, SDK trả phí…) thì đổi ở đây, màn hình không biết.
@MainActor
public final class PrintFlowContainer {
    public let library: FileLibrary
    public let converter: PDFConverter
    public let pageEditor: PDFPageEditor
    public let imageEditing: ImageEditingService
    public let printService: PrintService
    public var defaultSettings: PrintSettings

    public init(
        library: FileLibrary = FileLibrary.documents(),
        converter: PDFConverter = PDFConverter(),
        pageEditor: PDFPageEditor = PDFPageEditor(),
        imageEditing: ImageEditingService = ImageEditingService(),
        printService: PrintService = PrintService(),
        defaultSettings: PrintSettings = PrintSettings()
    ) {
        self.library = library
        self.converter = converter
        self.pageEditor = pageEditor
        self.imageEditing = imageEditing
        self.printService = printService
        self.defaultSettings = defaultSettings
    }

    public func makeFileList(onEdit: @escaping (SourceDocument) -> Void,
                             onPrint: @escaping ([SourceDocument]) -> Void) -> FileListViewController {
        FileListViewController(library: library, onEdit: onEdit, onPrint: onPrint)
    }

    /// Mỗi loại file một editor; ghi file xong mới báo thành công.
    func makeEditor(for document: SourceDocument, onSaved: @escaping (SourceDocument) -> Void) throws -> UIViewController {
        let onSave: EditorSaveHandler = { data, mode in
            onSaved(try self.library.save(data, for: document, mode: mode))
        }
        switch document.kind {
        case .pdf:
            guard let pdf = PDFDocument(url: document.url), !pdf.isLocked, pdf.pageCount > 0 else { throw PrintFlowError.unreadable(document.url) }
            return PDFFileEditorViewController(pdf: pdf, document: document, pageEditor: pageEditor, onSave: onSave)
        case .image:
            guard let image = UIImage(contentsOfFile: document.url.path) else { throw PrintFlowError.unreadable(document.url) }
            return ImageFileEditorViewController(image: image, document: document, imageEditing: imageEditing, onSave: onSave)
        case .text:
            // Thử UTF-8 trước, không được thì để hệ thống đoán encoding (UTF-16 có BOM…).
            var encoding = String.Encoding.utf8
            guard let text = (try? String(contentsOf: document.url, encoding: .utf8))
                ?? (try? String(contentsOf: document.url, usedEncoding: &encoding)) else { throw PrintFlowError.unreadable(document.url) }
            return TextFileEditorViewController(text: text, onSave: onSave)
        }
    }

    func makePreview(for documents: [SourceDocument]) throws -> UIViewController {
        let pdf = try converter.pdf(from: documents, settings: defaultSettings)
        let jobName = documents.count == 1 ? documents[0].name : "\(documents.count) tài liệu"
        return PrintPreviewViewController(pdf: pdf, documents: documents, settings: defaultSettings, converter: converter,
                                          pageEditor: pageEditor, printService: printService, jobName: jobName)
    }
}
