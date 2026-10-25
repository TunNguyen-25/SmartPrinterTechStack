import UIKit
import PDFKit
import QuickLook
import UniformTypeIdentifiers

final class DocumentPreviewViewController: UIViewController, QLPreviewControllerDataSource, QLPreviewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private(set) var markupImportTask: Task<LibraryDocument, Error>?
    private var document: LibraryDocument
    private let store: DocumentStore
    private let printService: PrintService
    private var previewTask: Task<Void, Never>?
    private var markupEnabled = false
    private var pendingMarkup: LibraryDocument?

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
        let editPDF = UIAction(title: "Sửa PDF", image: UIImage(systemName: "doc")) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(PDFEditorViewController(document: self.document, store: self.store), animated: true)
        }
        editPDF.accessibilityIdentifier = "editPDF"
        let editImage = UIAction(title: "Sửa ảnh", image: UIImage(systemName: "crop")) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(ImageEditorViewController(document: self.document, store: self.store), animated: true)
        }
        editImage.accessibilityIdentifier = "editImage"
        let markup = UIAction(title: "Quick Look / Markup", image: UIImage(systemName: "pencil.tip")) { [weak self] _ in self?.openMarkup() }
        markup.accessibilityIdentifier = "quickLookMarkup"
        let ext = document.url.pathExtension.lowercased()
        if ext != "pdf" { editPDF.attributes = .disabled }
        if !["jpg", "jpeg", "png", "heic"].contains(ext) { editImage.attributes = .disabled }
        if ext != "pdf" && !["jpg", "jpeg", "png", "heic"].contains(ext) { markup.attributes = .disabled }
        let menu = UIMenu(children: [
            editPDF, editImage, markup,
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
    private func openMarkup() {
        let source = document.url
        previewTask?.cancel()
        navigationItem.prompt = "Đang kiểm tra nội dung / quyền chỉnh sửa…"
        previewTask = Task {
            do {
                if source.pathExtension.lowercased() == "pdf" {
                    _ = try await PDFEditing.load(source: source)
                } else {
                    _ = try await ImageEditing.preview(source: source, edits: ImageEdits())
                }
                try Task.checkCancellation()
                guard QLPreviewController.canPreview(source as NSURL) else { throw CocoaError(.featureUnsupported) }
                markupEnabled = true
                pendingMarkup = nil
                let quickLook = QLPreviewController()
                quickLook.dataSource = self; quickLook.delegate = self
                quickLook.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeMarkup))
                let navigation = UINavigationController(rootViewController: quickLook)
                present(navigation, animated: true)
                navigation.presentationController?.delegate = self
                navigationItem.prompt = "Quick Look • dùng Markup nếu hệ thống hiện nút bút • lưu bản sao"
            } catch is CancellationError {} catch { showError(error) }
        }
    }
    @objc private func closeMarkup() {
        guard let navigation = presentedViewController as? UINavigationController,
              let quickLook = navigation.viewControllers.first as? QLPreviewController else { return }
        navigation.dismiss(animated: true) { [weak self] in self?.previewControllerDidDismiss(quickLook) }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        markupEnabled = false
        showSavedMarkup()
    }
    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        let ext = document.url.pathExtension.lowercased()
        // Quick Look decides whether to offer Markup for this content on the current OS.
        return markupEnabled || ["jpg", "jpeg", "png", "heic"].contains(ext) ? .createCopy : .disabled
    }
    func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem, at modifiedContentsURL: URL) {
        do {
            // Capture before returning: Quick Look owns the callback URL's lifetime.
            let staged = FileManager.default.temporaryDirectory.appendingPathComponent("markup-\(UUID()).\(modifiedContentsURL.pathExtension)")
            do { try FileManager.default.copyItem(at: modifiedContentsURL, to: staged) }
            catch { try? FileManager.default.removeItem(at: staged); throw error }
            let sourceName = document.url.deletingPathExtension().lastPathComponent
            let store = store
            let previous = markupImportTask
            markupImportTask = Task {
                defer { try? FileManager.default.removeItem(at: staged) }
                // Multiple save callbacks keep their order without discarding an earlier result.
                _ = try? await previous?.value
                let ext = try await DocumentPreviewLoader.editedCopyExtension(at: staged)
                return try await store.importFile(at: staged, preferredName: sourceName + "-markup." + ext)
            }
            guard let saving = markupImportTask else { return }
            Task {
                do {
                    let saved = try await saving.value
                    pendingMarkup = saved
                    navigationItem.prompt = "Đã lưu \(saved.name) vào thư viện."
                    if presentedViewController == nil { showSavedMarkup() }
                } catch { (presentedViewController ?? self).showError(error) }
            }
        } catch { (presentedViewController ?? self).showError(error) }
    }
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        markupEnabled = false
        showSavedMarkup()
    }
    private func showSavedMarkup() {
        guard let saved = pendingMarkup, let nav = navigationController else { return }
        pendingMarkup = nil
        nav.setViewControllers(Array(nav.viewControllers.dropLast()) + [DocumentPreviewViewController(document: saved, store: store, printService: printService)], animated: true)
    }

}
