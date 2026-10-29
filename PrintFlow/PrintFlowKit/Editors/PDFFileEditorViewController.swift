import UIKit
import PDFKit

/// Editor PDF: xoay/xoá/sắp xếp trang, ghi chú bằng Markup của hệ thống; lưu PDF.
@MainActor
public final class PDFFileEditorViewController: UIViewController {
    /// `var` vì Markup trả về một PDF mới.
    private(set) var pdf: PDFDocument
    private let pageEditor: PDFPageEditor
    let onSave: EditorSaveHandler
    private var hasChanges = false {
        didSet { navigationItem.rightBarButtonItem?.isEnabled = hasChanges }
    }
    let pdfView = PDFView()
    private let stack = UIStackView()
    private var thumbnailView = PDFThumbnailView()
    private(set) var deleteItem: UIBarButtonItem?

    init(pdf: PDFDocument, document: SourceDocument, pageEditor: PDFPageEditor, onSave: @escaping EditorSaveHandler) {
        self.pdf = pdf
        self.pageEditor = pageEditor
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        title = document.url.lastPathComponent
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Lưu", primaryAction: UIAction { [weak self] _ in self?.save() })
        navigationItem.rightBarButtonItem?.isEnabled = hasChanges
        // TODO: Hỏi bỏ thay đổi khi bấm Back mà chưa lưu.

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.document = pdf
        stack.addArrangedSubview(pdfView)
        reloadThumbnails()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        func item(_ title: String, _ symbol: String, _ action: @escaping (PDFFileEditorViewController) -> Void) -> UIBarButtonItem {
            UIBarButtonItem(title: title, image: UIImage(systemName: symbol), primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                action(self)
            })
        }
        let delete = item("Xoá", "trash") { $0.confirmDelete() }
        deleteItem = delete
        let buttons = [
            item("Xoay", "rotate.right") { $0.rotatePage(at: $0.currentIndex) },
            delete,
            item("Sắp xếp", "arrow.up.arrow.down") { $0.showReorder() },
            item("Ghi chú", "pencil.tip.crop.circle") { $0.showMarkup() },
        ]
        toolbarItems = Array(buttons.flatMap { [$0, .flexibleSpace()] }.dropLast())
        updateDeleteItem()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    private var currentIndex: Int {
        pdfView.currentPage.map(pdf.index(for:)) ?? 0
    }

    func rotatePage(at index: Int) {
        pageEditor.rotate(pdf, pageAt: index)
        didEditPages()
    }

    func deletePage(at index: Int) {
        pageEditor.delete(pdf, pageAt: index)
        didEditPages()
    }

    func reorder(_ order: [Int]) {
        pageEditor.reorder(pdf, to: order)
        didEditPages()
    }

    private func didEditPages() {
        hasChanges = true
        pdfView.layoutDocumentView()
        reloadThumbnails()
        updateDeleteItem()
    }

    /// PDFThumbnailView cache thumbnail theo trang, không vẽ lại khi xoay (gán lại pdfView/size cũng không ăn) nên tạo view mới.
    private func reloadThumbnails() {
        thumbnailView.removeFromSuperview()
        thumbnailView = PDFThumbnailView()
        thumbnailView.layoutMode = .horizontal
        thumbnailView.thumbnailSize = CGSize(width: 40, height: 56)
        thumbnailView.backgroundColor = .systemBackground
        thumbnailView.pdfView = pdfView
        thumbnailView.accessibilityLabel = "Danh sách trang"
        thumbnailView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.addArrangedSubview(thumbnailView)
    }

    private func updateDeleteItem() {
        // PDFPageEditor.delete đã chặn trang cuối, UI cũng phải phản ánh.
        deleteItem?.isEnabled = pdf.pageCount > 1
    }

    private func confirmDelete() {
        let index = currentIndex
        let alert = UIAlertController(title: "Xoá trang \(index + 1)?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xoá", style: .destructive) { [weak self] _ in self?.deletePage(at: index) })
        present(alert, animated: true)
    }

    private func showReorder() {
        let reorder = PageReorderViewController(pdf: pdf) { [weak self] order in
            guard let self else { return }
            if let order, order != Array(order.indices) { self.reorder(order) }
            self.dismiss(animated: true)
        }
        present(UINavigationController(rootViewController: reorder), animated: true)
    }

    private func showMarkup() {
        // Ghi ra file tạm để Markup thấy cả các thao tác trang chưa lưu; giữ tên gốc vì QuickLook hiện tên file.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("markup-\(UUID())")
        let url = folder.appendingPathComponent(title ?? "tai-lieu.pdf")
        do {
            guard let data = pdf.dataRepresentation() else { throw PrintFlowError.cannotEncode }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            showError(error)
            return
        }
        let markup = QuickLookMarkupController(url: url) { [weak self] edited in
            self?.replacePDF(with: edited)
        }
        present(markup, animated: true)
    }

    func replacePDF(with url: URL) {
        guard let edited = PDFDocument(url: url) else { return }
        pdf = edited
        pdfView.document = edited // thumbnailView theo pdfView
        hasChanges = true
        updateDeleteItem()
    }

    private func save() {
        SaveOptions.present(from: self, barButtonItem: navigationItem.rightBarButtonItem) { [weak self] mode in
            guard let self else { return }
            do {
                try self.onSave(self.makeData(), mode)
            } catch {
                self.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Không lưu được file", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func makeData() throws -> Data {
        guard let data = pdf.dataRepresentation() else { throw PrintFlowError.cannotEncode }
        return data
    }
}
