import UIKit
import PDFKit

final class PDFEditorViewController: UITableViewController {
    private struct Page {
        let index: Int
        let media: CGRect
        let originalCrop: CGRect
        var rotation = 0
        var crop: CGRect?
    }
    private let document: LibraryDocument
    private let store: DocumentStore
    private var pages: [Page] = []
    private var selected: Set<Int> = []
    private var appended: [LibraryDocument] = []
    private var task: Task<Void, Never>?
    private var thumbnails: [Int: Task<Void, Never>] = [:]

    init(document: LibraryDocument, store: DocumentStore) {
        self.document = document; self.store = store
        super.init(style: .insetGrouped)
        title = "Sửa PDF"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "cancelEditor"
        let save = UIBarButtonItem(title: "Lưu bản sao", style: .done, target: self, action: #selector(saveAll))
        save.accessibilityIdentifier = "saveEditedCopy"
        let tools = UIBarButtonItem(title: "Công cụ", menu: UIMenu(children: [
            UIAction(title: "Tách trang đã chọn") { [weak self] _ in self?.save(selectionOnly: true) },
            UIAction(title: "Ghép PDF từ thư viện…") { [weak self] _ in self?.chooseMerge() }
        ]))
        tools.accessibilityIdentifier = "pdfTools"
        navigationItem.rightBarButtonItems = [save, tools]
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.setEditing(true, animated: false)
        setBusy(true)
        task = Task {
            defer { task = nil; setBusy(false) }
            do {
                let pdf = try await PDFEditing.load(source: document.url)
                try Task.checkCancellation()
                pages = try (0..<pdf.pageCount).map { index in
                    guard let page = pdf.page(at: index) else { throw PDFEditing.Failure.corrupt }
                    return Page(index: index, media: page.bounds(for: .mediaBox), originalCrop: page.bounds(for: .cropBox))
                }
                reload()
            } catch is CancellationError {} catch { showError(error) }
        }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController == nil { task?.cancel(); thumbnails.values.forEach { $0.cancel() } }
    }
    private func setBusy(_ busy: Bool) {
        navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = !busy && !pages.isEmpty }
        tableView.isUserInteractionEnabled = !busy
        navigationItem.prompt = busy ? "Đang xử lý PDF… Có thể hủy." : "PDFKit • \(pages.count) trang + \(appended.count) PDF ghép"
    }
    private func reload() {
        thumbnails.values.forEach { $0.cancel() }; thumbnails = [:]
        tableView.reloadData()
        for (row, page) in pages.enumerated() where selected.contains(page.index) {
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
        setBusy(false)
    }
    @objc private func cancel() { task?.cancel(); navigationController?.popViewController(animated: true) }
    @objc private func saveAll() { save(selectionOnly: false) }
    private func save(selectionOnly: Bool) {
        guard task == nil else { return }
        let outputPages = selectionOnly ? pages.filter { selected.contains($0.index) } : pages
        guard !outputPages.isEmpty else { showError(PDFEditing.Failure.invalidPages); return }
        let indices = outputPages.map(\.index)
        let rotations = Dictionary(uniqueKeysWithValues: outputPages.map { ($0.index, $0.rotation) })
        let crops = Dictionary(uniqueKeysWithValues: outputPages.compactMap { page in page.crop.map { (page.index, $0) } })
        let source = document.url, additions = selectionOnly ? [] : appended.map(\.url)
        let name = source.deletingPathExtension().lastPathComponent + (selectionOnly ? "-split.pdf" : "-edited.pdf")
        setBusy(true)
        task = Task {
            defer { task = nil; setBusy(false) }
            do {
                let output = try await PDFEditing.export(source: source, pageIndices: indices, rotations: rotations, crops: crops, appending: additions)
                defer { try? FileManager.default.removeItem(at: output) }
                try Task.checkCancellation()
                let saved = try await store.importFile(at: output, preferredName: name)
                guard let nav = navigationController else { return }
                nav.setViewControllers(Array(nav.viewControllers.dropLast(2)) + [DocumentPreviewViewController(document: saved, store: store)], animated: true)
            } catch is CancellationError {} catch { showError(error) }
        }
    }
    private func chooseMerge() {
        guard task == nil else { return }
        task = Task {
            defer { task = nil }
            do {
                let documents = try await store.list().filter { $0.id != document.id && $0.url.pathExtension.lowercased() == "pdf" }
                guard !documents.isEmpty else {
                    let alert = UIAlertController(title: "Ghép PDF", message: "Nhập thêm PDF vào thư viện trước.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Đóng", style: .cancel)); present(alert, animated: true); return
                }
                let sheet = UIAlertController(title: "Thêm PDF ở cuối bản sao", message: "\(appended.count) tài liệu đã chọn. Thứ tự theo lần thêm.", preferredStyle: .actionSheet)
                for item in documents {
                    sheet.addAction(UIAlertAction(title: item.name, style: .default) { [weak self] _ in
                        self?.appended.append(item); self?.setBusy(false)
                    })
                }
                sheet.addAction(UIAlertAction(title: "Bỏ các PDF ghép", style: .destructive) { [weak self] _ in self?.appended = []; self?.setBusy(false) })
                sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
                sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
                present(sheet, animated: true)
            } catch { showError(error) }
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "Chọn trang để tách • Kéo tay nắm để đổi thứ tự" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { "Mọi thay đổi chỉ lưu vào bản sao. Crop box dùng tọa độ PDF trước xoay, gốc trái dưới; nội dung ngoài crop vẫn tồn tại. Không phải redaction hoặc sửa chữ gốc." }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { pages.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let page = pages[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.accessibilityIdentifier = "pdfPage-\(page.index)"
        cell.textLabel?.text = "Trang gốc \(page.index + 1)"
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.text = "Xoay thêm \(page.rotation)°\(page.crop == nil ? "" : " • đã crop")"
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .caption1)
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.imageView?.image = UIImage(systemName: "doc")
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.accessibilityLabel = "Thao tác trang \(page.index + 1)"
        button.accessibilityIdentifier = "pageActions-\(page.index)"
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.menu = UIMenu(children: [
            UIAction(title: "Xoay 90°") { [weak self] _ in self?.change(page.index) { $0.rotation = ($0.rotation + 90) % 360 } },
            UIAction(title: "Crop box…") { [weak self] _ in self?.crop(page.index) },
            UIAction(title: "Bỏ crop") { [weak self] _ in self?.change(page.index) { $0.crop = nil } },
            UIAction(title: "Xóa trang", attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                guard self.pages.count > 1 else { self.showError(PDFEditing.Failure.invalidPages); return }
                self.pages.removeAll { $0.index == page.index }; self.selected.remove(page.index); self.reload()
            }
        ])
        button.showsMenuAsPrimaryAction = true
        cell.editingAccessoryView = button
        thumbnails[page.index]?.cancel()
        let source = document.url
        thumbnails[page.index] = Task { [weak cell] in
            do {
                let image = try await PDFEditing.thumbnail(source: source, index: page.index, rotation: page.rotation, crop: page.crop)
                guard !Task.isCancelled else { return }
                cell?.imageView?.image = image; cell?.setNeedsLayout()
            } catch { /* The load/export paths surface document errors. */ }
        }
        return cell
    }
    private func change(_ index: Int, operation: (inout Page) -> Void) {
        guard let row = pages.firstIndex(where: { $0.index == index }) else { return }
        operation(&pages[row]); reload()
    }
    private func crop(_ index: Int) {
        guard let page = pages.first(where: { $0.index == index }) else { return }
        let box = page.crop ?? page.originalCrop
        presentEditFields(title: "Crop box PDF (pt, trước xoay)", labels: ["x", "y", "width", "height"], values: [box.minX, box.minY, box.width, box.height]) { [weak self] values in
            let crop = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            guard crop.width > 0, crop.height > 0, page.media.contains(crop) else { self?.showError(PDFEditing.Failure.invalidCrop); return }
            self?.change(index) { $0.crop = crop }
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { selected.insert(pages[indexPath.row].index) }
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) { selected.remove(pages[indexPath.row].index) }
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        pages.insert(pages.remove(at: sourceIndexPath.row), at: destinationIndexPath.row); reload()
    }
}
