import UIKit
import PDFKit
import UniformTypeIdentifiers

/// Danh sách file sẽ ghép (PDF gốc ở đầu). Thêm từ Files, kéo để đổi thứ tự file, vuốt để bỏ.
final class PDFMergeViewController: UITableViewController, UIDocumentPickerDelegate {
    // Giữ các PDFDocument nguồn sống tới lúc ghi xong, vì trang copy vẫn tham chiếu tài liệu gốc.
    private var files: [(name: String, document: PDFDocument)]
    private let onSave: @MainActor (URL) -> Void

    init(document: PDFDocument, name: String, onSave: @escaping @MainActor (URL) -> Void) {
        files = [(name, document)]
        self.onSave = onSave
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addCancelSave(save: #selector(save))
        let add = UIBarButtonItem(systemItem: .add, menu: UIMenu(children: [
            UIAction(title: "Chọn PDF từ Files…", image: UIImage(systemName: "folder")) { [weak self] _ in self?.pick() },
            // Để thử trên simulator chưa có PDF nào trong Files.
            UIAction(title: "Thêm bản sao PDF gốc", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                guard let self, let first = files.first else { return }
                files.append((first.name + " (bản sao)", first.document))
                tableView.reloadData()
            }
        ]))
        add.accessibilityLabel = "Thêm PDF"
        navigationItem.rightBarButtonItems = [navigationItem.rightBarButtonItem!, add]
        tableView.setEditing(true, animated: false)
    }

    private func pick() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var rejected: [String] = []
        for url in urls {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.allowsDocumentAssembly, pdf.pageCount > 0 else {
                rejected.append(url.lastPathComponent)
                continue
            }
            files.append((url.lastPathComponent, pdf))
        }
        tableView.reloadData()
        if !rejected.isEmpty { alert("Bỏ qua file hỏng hoặc bị khóa:\n" + rejected.joined(separator: "\n")) }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "Thứ tự ghép" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Tổng \(files.reduce(0) { $0 + $1.document.pageCount }) trang. Mục lục (bookmark) của các file không được giữ."
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { files.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let file = files[indexPath.row]
        cell.textLabel?.text = file.name
        cell.detailTextLabel?.text = "\(file.document.pageCount) trang"
        cell.imageView?.image = file.document.page(at: 0)?.thumbnail(of: CGSize(width: 40, height: 56), for: .cropBox)
        return cell
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        files.insert(files.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        files.remove(at: indexPath.row)
        tableView.reloadData()
    }

    @objc private func save() {
        guard files.count >= 2 else { return alert("Cần ít nhất 2 file để ghép.") }
        let merged = PDFDocument()
        for file in files {
            for index in 0..<file.document.pageCount {
                guard let page = file.document.page(at: index)?.copy() as? PDFPage else { continue }
                merged.insert(page, at: merged.pageCount)
            }
        }
        finish(writing: merged, prefix: "merge", onSave: onSave)
    }
}
