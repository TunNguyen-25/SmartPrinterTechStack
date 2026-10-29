import UIKit
import PDFKit

/// Editor PDF: thao tác trang, markup (Quick Look / PencilKit / PaperKit — xem PDFEditorKit).
public final class PDFFileEditorViewController: UIViewController {
    private let pdf: PDFDocument
    private let pageEditor: PDFPageEditor
    private let onFinish: (PDFDocument) -> Void

    init(pdf: PDFDocument, pageEditor: PDFPageEditor, onFinish: @escaping (PDFDocument) -> Void) {
        self.pdf = pdf
        self.pageEditor = pageEditor
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        title = "Sửa PDF"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Tiếp", primaryAction: UIAction { [weak self] _ in self?.finish() })
        // TODO: UI — PDFView + thumbnail, nút xoay/xoá/sắp xếp gọi pageEditor, nút markup.
    }

    private func finish() { onFinish(pdf) }
}
