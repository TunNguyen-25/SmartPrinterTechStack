import UIKit
import PDFKit
import QuickLook
import UniformTypeIdentifiers

final class DocumentPreviewViewController: UIViewController, QLPreviewControllerDataSource {
    private var document: LibraryDocument
    private let store: DocumentStore
    private let printService: PrintService
    private var previewTask: Task<Void, Never>?

    init(document: LibraryDocument, store: DocumentStore, printService: PrintService? = nil) {
        self.document = document
        self.store = store
        self.printService = printService ?? .shared
        super.init(nibName: nil, bundle: nil)
        title = document.name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureActions()
        loadPreview()
    }
    private func configureActions() {
        let printAction = UIAction(title: "In qua hệ thống", image: UIImage(systemName: "printer")) { [weak self] _ in
            guard let self else { return }
            self.printService.presentPrint(document: self.document, from: self)
        }
        printAction.accessibilityIdentifier = "printDocument"
        let directAction = UIAction(title: "In trực tiếp…", image: UIImage(systemName: "printer.fill")) { [weak self] _ in
            guard let self else { return }
            self.printService.presentDirectPrint(document: self.document, from: self)
        }
        directAction.accessibilityIdentifier = "directPrint"
        let printable = document.url.pathExtension.lowercased() == "pdf" || UTType(filenameExtension: document.url.pathExtension)?.conforms(to: .image) == true
        if !printable { printAction.attributes = .disabled; directAction.attributes = .disabled }
        let menu = UIMenu(children: [
            printAction, directAction,
            UIAction(title: "Chia sẻ", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share() },
            UIAction(title: "Xuất sang Files", image: UIImage(systemName: "folder")) { [weak self] _ in self?.export() },
            UIAction(title: "Đổi tên", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.rename() },
            UIAction(title: "Xóa", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.confirmDelete() }
        ])
        let button = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
        button.accessibilityIdentifier = "documentActions"
        button.accessibilityLabel = "Thao tác tài liệu"
        navigationItem.rightBarButtonItem = button
    }
    private func loadPreview() {
        previewTask?.cancel()
        children.forEach { child in child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        view.subviews.forEach { $0.removeFromSuperview() }
        let url = document.url
        if url.pathExtension.lowercased() == "pdf" {
            navigationItem.prompt = "PDFKit • iOS 15+"
            previewTask = Task {
                do {
                    let pdf = try await DocumentPreviewLoader.pdf(at: url)
                    guard !Task.isCancelled else { return }
                    if pdf.isLocked { showMessage("PDF đang khóa; chưa thể preview."); return }
                    let pdfView = PDFView()
                    pdfView.autoScales = true
                    pdfView.document = pdf
                    embed(pdfView)
                } catch { if !Task.isCancelled { showMessage("Không mở được PDF: \(error.localizedDescription)") } }
            }
        } else if UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
            navigationItem.prompt = "Image I/O • preview ≤ 2048 px • chia sẻ bản gốc"
            previewTask = Task {
                do {
                    let image = try await DocumentPreviewLoader.image(at: url)
                    guard !Task.isCancelled else { return }
                    let imageView = UIImageView(image: image)
                    imageView.contentMode = .scaleAspectFit
                    imageView.isAccessibilityElement = true
                    imageView.accessibilityLabel = document.name
                    embed(imageView)
                } catch { if !Task.isCancelled { showMessage("Không mở được ảnh: \(error.localizedDescription)") } }
            }
        } else if QLPreviewController.canPreview(url as NSURL) {
            navigationItem.prompt = "Quick Look • chỉ preview khi hệ thống hỗ trợ"
            let quickLook = QLPreviewController()
            quickLook.dataSource = self
            addChild(quickLook)
            embed(quickLook.view)
            quickLook.didMove(toParent: self)
        } else {
            showMessage("Hệ thống không hỗ trợ preview định dạng này. Bạn vẫn có thể chia sẻ hoặc xuất file gốc.")
        }
    }
    private func embed(_ content: UIView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    private func showMessage(_ text: String) {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = text
        embed(label)
    }
    private func share() {
        let sheet = UIActivityViewController(activityItems: [document.url], applicationActivities: nil)
        sheet.excludedActivityTypes = [.print]
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }
    private func export() {
        let picker = UIDocumentPickerViewController(forExporting: [document.url], asCopy: true)
        picker.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(picker, animated: true)
    }
    private func rename() {
        let alert = UIAlertController(title: "Đổi tên", message: "Giữ phần mở rộng để chọn đúng công cụ preview.", preferredStyle: .alert)
        alert.addTextField { [document] field in
            field.text = document.name
            field.clearButtonMode = .always
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text else { return }
            Task {
                do {
                    self.document = try await self.store.rename(id: self.document.id, to: name)
                    self.title = self.document.name
                    self.configureActions()
                    self.loadPreview()
                } catch { self.showError(error) }
            }
        })
        present(alert, animated: true)
    }
    private func confirmDelete() {
        let alert = UIAlertController(title: "Xóa tài liệu?", message: document.name, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Xóa", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    self.previewTask?.cancel()
                    try await self.store.delete(id: self.document.id)
                    await DocumentThumbnailCache.shared.remove(for: self.document.id)
                    self.navigationController?.popViewController(animated: true)
                } catch { self.showError(error) }
            }
        })
        present(alert, animated: true)
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { document.url as NSURL }
}
