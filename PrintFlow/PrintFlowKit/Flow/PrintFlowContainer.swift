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

    /// Mỗi loại file một editor; tất cả kết thúc bằng PDF.
    func makeEditor(for document: SourceDocument, onFinish: @escaping (PDFDocument) -> Void) throws -> UIViewController {
        switch document.kind {
        case .pdf:
            guard let pdf = PDFDocument(url: document.url), !pdf.isLocked, pdf.pageCount > 0 else { throw PrintFlowError.unreadable(document.url) }
            return PDFFileEditorViewController(pdf: pdf, pageEditor: pageEditor, onFinish: onFinish)
        case .image:
            guard let image = UIImage(contentsOfFile: document.url.path) else { throw PrintFlowError.unreadable(document.url) }
            return ImageFileEditorViewController(image: image, imageEditing: imageEditing, converter: converter, settings: defaultSettings, onFinish: onFinish)
        case .text:
            let text = try String(contentsOf: document.url, encoding: .utf8)
            return TextFileEditorViewController(text: text, converter: converter, settings: defaultSettings, onFinish: onFinish)
        }
    }

    func makePreview(for pdf: PDFDocument, jobName: String) -> UIViewController {
        PrintPreviewViewController(pdf: pdf, settings: defaultSettings, pageEditor: pageEditor, printService: printService, jobName: jobName)
    }

    /// Tạm xem trước file đầu tiên; task 03 sẽ ghép toàn bộ danh sách.
    func makePreview(for documents: [SourceDocument]) throws -> UIViewController? {
        guard let document = documents.first else { return nil }
        let pdf: PDFDocument
        switch document.kind {
        case .pdf:
            guard let source = PDFDocument(url: document.url), !source.isLocked, source.pageCount > 0 else {
                throw PrintFlowError.unreadable(document.url)
            }
            pdf = source
        case .image:
            guard let image = UIImage(contentsOfFile: document.url.path) else { throw PrintFlowError.unreadable(document.url) }
            pdf = converter.pdf(from: [image], pageSize: defaultSettings.pageSize)
        case .text:
            pdf = converter.pdf(from: try String(contentsOf: document.url, encoding: .utf8), style: TextStyle(), pageSize: defaultSettings.pageSize)
        }
        return makePreview(for: pdf, jobName: document.name)
    }
}
