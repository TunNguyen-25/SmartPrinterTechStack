import UIKit
import UniformTypeIdentifiers

/// Danh sách dùng chung cho sửa file và chọn tài liệu theo thứ tự in.
@MainActor
public final class FileListViewController: UITableViewController, UIDocumentPickerDelegate {
    private let library: FileLibrary
    private let onEdit: (SourceDocument) -> Void
    private let onPrint: ([SourceDocument]) -> Void
    private var items: [FileLibrary.Item] = []
    private var selectionOrder: [URL] = []
    private let byteFormatter = ByteCountFormatter()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    private lazy var printButton = UIBarButtonItem(title: "Xem trước in (0)", style: .plain,
                                                  target: self, action: #selector(printSelected))

    init(library: FileLibrary, onEdit: @escaping (SourceDocument) -> Void,
         onPrint: @escaping ([SourceDocument]) -> Void) {
        self.library = library
        self.onEdit = onEdit
        self.onPrint = onPrint
        super.init(style: .plain)
        title = "Tài liệu"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "File")
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        toolbarItems = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), printButton]
        updateControls()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        navigationController?.setToolbarHidden(!isEditing, animated: animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    public func reload() {
        loadViewIfNeeded()
        items = library.items()
        let available = Set(items.map { $0.document.url })
        selectionOrder.removeAll { !available.contains($0) }
        tableView.reloadData()
        if isEditing {
            for (row, item) in items.enumerated() where selectionOrder.contains(item.document.url) {
                tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
            }
        }
        if items.isEmpty {
            let label = UILabel()
            label.text = "Chưa có tài liệu. Bấm + để thêm."
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
        updateControls()
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "File", for: indexPath)
        let item = items[indexPath.row]
        let kind: String
        let symbol: String
        switch item.document.kind {
        case .pdf: (kind, symbol) = ("PDF", "doc.richtext")
        case .image: (kind, symbol) = ("Ảnh", "photo")
        case .text: (kind, symbol) = ("TXT", "doc.plaintext")
        }
        var content = UIListContentConfiguration.subtitleCell()
        content.text = item.document.url.lastPathComponent
        content.secondaryText = "\(kind) • \(byteFormatter.string(fromByteCount: Int64(item.byteCount))) • \(dateFormatter.string(from: item.modifiedAt))"
        content.image = UIImage(systemName: symbol)
        cell.contentConfiguration = content
        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let document = items[indexPath.row].document
        if isEditing {
            if !selectionOrder.contains(document.url) { selectionOrder.append(document.url) }
            updateControls()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let sheet = UIAlertController(title: document.url.lastPathComponent, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Sửa", style: .default) { [weak self] _ in self?.onEdit(document) })
        sheet.addAction(UIAlertAction(title: "Xem trước in", style: .default) { [weak self] _ in self?.onPrint([document]) })
        sheet.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            let cell = tableView.cellForRow(at: indexPath)
            popover.sourceView = cell ?? tableView
            popover.sourceRect = cell?.bounds ?? tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }

    public override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard isEditing else { return }
        selectionOrder.removeAll { $0 == items[indexPath.row].document.url }
        updateControls()
    }

    public override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath,
                                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isEditing else { return nil }
        let document = items[indexPath.row].document
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Sửa", image: UIImage(systemName: "pencil")) { _ in self?.onEdit(document) },
                UIAction(title: "Xem trước in", image: UIImage(systemName: "printer")) { _ in self?.onPrint([document]) },
                UIAction(title: "Xoá", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.delete(document)
                }
            ])
        }
    }

    public override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isEditing else { return nil }
        let document = items[indexPath.row].document
        let action = UIContextualAction(style: .destructive, title: "Xoá") { [weak self] _, _, completion in
            completion(self?.delete(document) ?? false)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    public override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    public override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }

    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        if !editing {
            selectionOrder.removeAll()
            for path in tableView.indexPathsForSelectedRows ?? [] { tableView.deselectRow(at: path, animated: false) }
        }
        updateControls()
        navigationController?.setToolbarHidden(!editing, animated: animated)
    }

    private func updateControls() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: isEditing ? "Xong" : "Chọn", style: .plain,
                                                           target: self, action: #selector(toggleSelection))
        if isEditing {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: allSelected ? "Bỏ chọn" : "Chọn tất cả", style: .plain,
                                                              target: self, action: #selector(toggleAll))
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(importFiles))
            navigationItem.leftBarButtonItem?.accessibilityLabel = "Thêm tài liệu"
        }
        printButton.title = "Xem trước in (\(selectionOrder.count))"
        printButton.isEnabled = !selectionOrder.isEmpty
    }

    private var allSelected: Bool { !items.isEmpty && selectionOrder.count == items.count }

    @objc private func toggleSelection() { setEditing(!isEditing, animated: true) }

    @objc private func toggleAll() {
        if allSelected {
            selectionOrder.removeAll()
            for path in tableView.indexPathsForSelectedRows ?? [] { tableView.deselectRow(at: path, animated: false) }
        } else {
            for (row, item) in items.enumerated() {
                if !selectionOrder.contains(item.document.url) { selectionOrder.append(item.document.url) }
                tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
            }
        }
        updateControls()
    }

    @objc private func printSelected() {
        let documents = Dictionary(uniqueKeysWithValues: items.map { ($0.document.url, $0.document) })
        let selected = selectionOrder.compactMap { documents[$0] }
        guard !selected.isEmpty else { return }
        onPrint(selected)
        setEditing(false, animated: false)
    }

    @objc private func importFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image, .plainText], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var errors: [String] = []
        for url in urls {
            do { _ = try library.importFile(at: url) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        reload()
        if !errors.isEmpty {
            // Đợi picker đóng xong trước khi trình bày thông báo lỗi.
            controller.dismiss(animated: true) { [weak self] in
                self?.showError(title: "Không thêm được một số file", message: errors.joined(separator: "\n"))
            }
        }
    }

    @discardableResult
    private func delete(_ document: SourceDocument) -> Bool {
        do {
            try library.delete(document)
            reload()
            return true
        } catch {
            showError(title: "Không xoá được file", message: error.localizedDescription)
            return false
        }
    }

    private func showError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
