import UIKit
import UniformTypeIdentifiers

final class PrinterViewController: UITableViewController {
    private let store: DocumentStore
    private let printService: PrintService
    private var documents: [LibraryDocument] = []
    private var selected: [LibraryDocument] = []
    private var generationTask: Task<Void, Never>?

    init(store: DocumentStore, printService: PrintService? = nil) {
        self.store = store
        self.printService = printService ?? .shared
        super.init(style: .insetGrouped)
        title = "Printer"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.prompt = "UIKit Printing • AirPrint • iOS 15+"
        tableView.allowsMultipleSelectionDuringEditing = true
        configureButtons()
        NotificationCenter.default.addObserver(self, selector: #selector(statusUpdated), name: PrintService.statusChanged, object: printService)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            do {
                documents = try await store.list()
                tableView.reloadData()
            } catch { showError(error) }
        }
    }
    @objc private func statusUpdated() { tableView.reloadSections(IndexSet(integer: 0), with: .none) }

    private func configureButtons() {
        if isEditing {
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancelSelection))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Ghép và review", style: .done, target: self, action: #selector(combineImages))
        } else {
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Chọn nhiều ảnh", style: .plain, target: self, action: #selector(selectImages))
        }
    }
    @objc private func selectImages() {
        selected = []
        setEditing(true, animated: true)
        configureButtons()
        navigationItem.prompt = "Chạm ảnh theo thứ tự trang muốn in; chỉ JPEG/PNG/HEIC."
        tableView.reloadData()
    }
    @objc private func cancelSelection() {
        generationTask?.cancel()
        selected = []
        setEditing(false, animated: true)
        configureButtons()
        navigationItem.prompt = "UIKit Printing • AirPrint • iOS 15+"
        tableView.reloadData()
    }
    @objc private func combineImages() {
        guard generationTask == nil else { return }
        let urls = selected.map(\.url)
        generate(name: "Images-\(UUID().uuidString.prefix(8)).pdf") {
            try await PrintPreparation.imagesPDF(at: urls)
        }
    }
    private func generate(name: String, operation: @escaping @Sendable () async throws -> URL) {
        guard generationTask == nil else { return }
        navigationItem.prompt = "Đang tạo PDF từng trang…"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancelSelection))
        navigationItem.rightBarButtonItem?.isEnabled = false
        generationTask = Task {
            defer {
                generationTask = nil
                if isEditing { cancelSelection() }
                configureButtons()
                navigationItem.prompt = "UIKit Printing • AirPrint • iOS 15+"
            }
            do {
                let url = try await operation()
                defer { try? FileManager.default.removeItem(at: url) }
                try Task.checkCancellation()
                let document = try await store.importFile(at: url, preferredName: name)
                navigationController?.pushViewController(DocumentPreviewViewController(document: document, store: store, printService: printService), animated: true)
            } catch is CancellationError {
                navigationItem.prompt = "Đã hủy tạo PDF."
            } catch { showError(error) }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 3 : section == 1 ? 2 : documents.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Máy in", "Trang kiểm tra kích thước", "Thư viện chung — chọn để review trước khi in"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: "Picker hệ thống tìm máy AirPrint. Cùng mạng và máy in đang bật. Capability chỉ xác minh sau khi liên hệ thành công."
        case 1: "Mở PDF để review, chọn đúng A4/Letter ở print sheet. In 100% / Actual Size nếu máy hỗ trợ; dùng thước đo đoạn 100 mm trên giấy."
        default: "Thêm file/ảnh ở tab File. Chọn nhiều ảnh theo thứ tự chạm → Ghép và review để lưu một PDF mới. PDF/ảnh được in; Office và loại khác cần chuyển đổi trước."
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        if indexPath.section == 0 {
            content.text = [printService.status, "Chọn / đổi máy in", "Kiểm tra lại kết nối và capability"][indexPath.row]
            cell.accessibilityIdentifier = ["printerStatus", "choosePrinter", "refreshPrinter"][indexPath.row]
            cell.selectionStyle = indexPath.row == 0 ? .none : .default
        } else if indexPath.section == 1 {
            let paper = PrintPaperSize.allCases[indexPath.row]
            content.text = "Calibration \(paper.rawValue)"
            content.secondaryText = "PDF vector • thước 100 mm • viền 0.5 inch • ô màu"
            cell.accessibilityIdentifier = "calibration\(paper.rawValue)"
            cell.accessoryType = .disclosureIndicator
        } else {
            let document = documents[indexPath.row]
            content.text = document.name
            if let index = selected.firstIndex(where: { $0.id == document.id }) {
                content.secondaryText = "Trang \(index + 1)"
            } else { content.secondaryText = document.url.pathExtension.uppercased() }
            cell.accessibilityIdentifier = "printerDocument-\(document.id)"
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 2 && UTType(filenameExtension: documents[indexPath.row].url.pathExtension)?.conforms(to: .image) == true
    }
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard generationTask == nil else { return nil }
        if isEditing && !self.tableView(tableView, canEditRowAt: indexPath) { return nil }
        return indexPath
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditing {
            selected.append(documents[indexPath.row])
            updateOrderLabels()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if indexPath.row == 1 { printService.choosePrinter(from: self) }
            if indexPath.row == 2 { printService.refreshPrinter(from: self) }
        } else if indexPath.section == 1 {
            let paper = PrintPaperSize.allCases[indexPath.row]
            generate(name: "Calibration-\(paper.rawValue).pdf") { try await PrintPreparation.calibration(paper: paper) }
        } else {
            navigationController?.pushViewController(DocumentPreviewViewController(document: documents[indexPath.row], store: store, printService: printService), animated: true)
        }
    }
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard isEditing, indexPath.section == 2 else { return }
        selected.removeAll { $0.id == documents[indexPath.row].id }
        updateOrderLabels()
    }
    private func updateOrderLabels() {
        for path in tableView.indexPathsForVisibleRows ?? [] where path.section == 2 {
            guard let cell = tableView.cellForRow(at: path) else { continue }
            var content = cell.defaultContentConfiguration()
            let document = documents[path.row]
            content.text = document.name
            content.textProperties.numberOfLines = 0
            content.secondaryText = selected.firstIndex(where: { $0.id == document.id }).map { "Trang \($0 + 1)" } ?? document.url.pathExtension.uppercased()
            cell.contentConfiguration = content
        }
    }
}
