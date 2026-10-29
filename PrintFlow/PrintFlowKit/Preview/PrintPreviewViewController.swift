import UIKit
import PDFKit

/// Màn chung cuối flow: xem trước PDF, sửa nhẹ trang (pageEditor), chỉnh PrintSettings, rồi in.
/// Mọi thay đổi chỉ áp dụng cho lần in này, không ghi vào file trong thư viện.
public final class PrintPreviewViewController: UIViewController {
    private(set) var pdf: PDFDocument
    private(set) var settings: PrintSettings
    private let documents: [SourceDocument]
    private let converter: PDFConverter
    private let pageEditor: PDFPageEditor
    private let printService: PrintService
    private(set) var hasPageEdits = false
    let pdfView = PDFView()
    private let stack = UIStackView()
    private var thumbnailView = PDFThumbnailView()
    private let paperButton = UIButton(type: .system)
    private let orientationButton = UIButton(type: .system)
    private let grayscaleSwitch = UISwitch()
    /// Phủ lên pdfView để preview hiện xám khi bật Đen trắng.
    private let grayscaleOverlay = UIView()
    private var deleteItem: UIBarButtonItem?

    init(pdf: PDFDocument, documents: [SourceDocument], settings: PrintSettings, converter: PDFConverter,
         pageEditor: PDFPageEditor, printService: PrintService, jobName: String) {
        self.pdf = pdf
        self.documents = documents
        self.settings = settings
        self.converter = converter
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

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.document = pdf
        grayscaleOverlay.isUserInteractionEnabled = false
        grayscaleOverlay.backgroundColor = .white
        grayscaleOverlay.layer.compositingFilter = "saturationBlendMode"
        grayscaleOverlay.frame = pdfView.bounds
        grayscaleOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pdfView.addSubview(grayscaleOverlay)
        stack.addArrangedSubview(pdfView)
        stack.addArrangedSubview(makeSettingsBar())
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

        func item(_ title: String, _ symbol: String, _ action: @escaping (PrintPreviewViewController) -> Void) -> UIBarButtonItem {
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
        ]
        toolbarItems = Array(buttons.flatMap { [$0, .flexibleSpace()] }.dropLast())
        updateSettingsBar()
        updatePages()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    private var currentIndex: Int {
        pdfView.currentPage.map(pdf.index(for:)) ?? 0
    }

    // MARK: Thiết lập in

    private func makeSettingsBar() -> UIView {
        for button in [paperButton, orientationButton] {
            button.showsMenuAsPrimaryAction = true
        }
        grayscaleSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            var new = self.settings
            new.grayscale = self.grayscaleSwitch.isOn
            self.change(to: new)
        }, for: .valueChanged)
        let grayscaleLabel = UILabel()
        grayscaleLabel.text = "Đen trắng"
        grayscaleLabel.font = .preferredFont(forTextStyle: .body)
        grayscaleLabel.adjustsFontForContentSizeCategory = true
        grayscaleSwitch.accessibilityLabel = "Đen trắng"
        let bar = UIStackView(arrangedSubviews: [paperButton, orientationButton, UIView(), grayscaleLabel, grayscaleSwitch])
        bar.spacing = 12
        bar.alignment = .center
        bar.isLayoutMarginsRelativeArrangement = true
        bar.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return bar
    }

    private func updateSettingsBar() {
        func menu<T: Equatable>(_ options: [(String, T)], current: T, set: @escaping (inout PrintSettings, T) -> Void) -> UIMenu {
            UIMenu(children: options.map { title, value in
                UIAction(title: title, state: value == current ? .on : .off) { [weak self] _ in
                    guard let self, value != current else { return }
                    var new = self.settings
                    set(&new, value)
                    self.change(to: new)
                }
            })
        }
        let papers: [(String, PrintSettings.Paper)] = [("A4", .a4), ("Letter", .letter)]
        let paperName = papers.first { $0.1 == settings.paper }?.0 ?? ""
        paperButton.setTitle("Khổ: \(paperName) ▾", for: .normal)
        paperButton.menu = menu(papers, current: settings.paper) { $0.paper = $1 }
        orientationButton.setTitle("Hướng: \(settings.isLandscape ? "Ngang" : "Dọc") ▾", for: .normal)
        orientationButton.menu = menu([("Dọc", false), ("Ngang", true)], current: settings.isLandscape) { $0.isLandscape = $1 }
        grayscaleSwitch.isOn = settings.grayscale
        grayscaleOverlay.isHidden = !settings.grayscale
    }

    /// Đen trắng chỉ đổi cờ; đổi khổ/hướng phải convert lại nên hỏi trước nếu đã sửa trang.
    private func change(to new: PrintSettings) {
        guard new.pageSize != settings.pageSize else {
            settings = new
            updateSettingsBar()
            return
        }
        guard hasPageEdits else {
            reconvert(with: new)
            return
        }
        let alert = UIAlertController(title: "Đổi khổ giấy sẽ huỷ các thay đổi trang. Tiếp tục?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        alert.addAction(UIAlertAction(title: "Tiếp tục", style: .destructive) { [weak self] _ in self?.reconvert(with: new) })
        present(alert, animated: true)
    }

    /// Convert lại theo khổ mới, bỏ mọi chỉnh sửa trang.
    func reconvert(with new: PrintSettings) {
        do {
            pdf = try converter.pdf(from: documents, settings: new)
        } catch {
            let alert = UIAlertController(title: "Không chuyển được sang PDF", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        settings = new
        hasPageEdits = false
        pdfView.document = pdf
        reloadThumbnails()
        updateSettingsBar()
        updatePages()
    }

    // MARK: Thao tác trang

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
        hasPageEdits = true
        pdfView.layoutDocumentView()
        reloadThumbnails()
        updatePages()
    }

    /// PDFThumbnailView không vẽ lại khi xoay trang nên tạo view mới (xem PDFFileEditorViewController).
    private func reloadThumbnails() {
        thumbnailView.removeFromSuperview()
        thumbnailView = PDFThumbnailView()
        thumbnailView.layoutMode = .horizontal
        thumbnailView.thumbnailSize = CGSize(width: 40, height: 56)
        thumbnailView.backgroundColor = .systemBackground
        thumbnailView.pdfView = pdfView
        thumbnailView.accessibilityLabel = "Danh sách trang"
        thumbnailView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.insertArrangedSubview(thumbnailView, at: 1)
    }

    private func updatePages() {
        navigationItem.prompt = "\(pdf.pageCount) trang"
        // PDFPageEditor.delete đã chặn trang cuối, UI cũng phải phản ánh.
        deleteItem?.isEnabled = pdf.pageCount > 1
    }

    private func confirmDelete() {
        let index = currentIndex
        let alert = UIAlertController(title: "Xoá trang \(index + 1)?", message: "Chỉ áp dụng cho lần in này.", preferredStyle: .alert)
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

    private func print(from item: UIBarButtonItem?) {
        printService.print(pdf, settings: settings, jobName: title ?? "Document", from: item)
    }
}
