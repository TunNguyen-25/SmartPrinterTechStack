import UIKit
import PDFKit

/// Màn chung cuối flow: xem trước PDF, sửa nhẹ trang (pageEditor), chỉnh PrintSettings, rồi in.
public final class PrintPreviewViewController: UIViewController {
    private let pdf: PDFDocument
    private var settings: PrintSettings
    private let pageEditor: PDFPageEditor
    private let printService: PrintService

    init(pdf: PDFDocument, settings: PrintSettings, pageEditor: PDFPageEditor, printService: PrintService, jobName: String) {
        self.pdf = pdf
        self.settings = settings
        self.pageEditor = pageEditor
        self.printService = printService
        super.init(nibName: nil, bundle: nil)
        title = jobName
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "In", primaryAction: UIAction { [weak self] action in
            self?.print(from: action.sender as? UIBarButtonItem)
        })
        // TODO: UI — PDFView + PDFThumbnailView, xoay/xoá/sắp xếp trang qua pageEditor,
        // panel khổ giấy / hướng / đen trắng sửa `settings`.
    }

    private func print(from item: UIBarButtonItem?) {
        printService.print(pdf, settings: settings, jobName: title ?? "Document", from: item)
    }
}
