import UIKit
import PDFKit

/// Các thao tác trang bằng PDFKit, mỗi tool một màn riêng. Tool tự dismiss; `onSave` nhận file PDF mới
/// trong thư mục tạm (Split gọi một lần cho mỗi file tách ra).
public enum PDFPageTool: String, CaseIterable, Sendable {
    case crop = "Crop"
    case rotate = "Rotate (1 trang / cả PDF)"
    case split = "Split"
    case merge = "Merge"
    case reorder = "Reorder"

    /// nil khi PDF không mở được, bị khóa hoặc cấm sửa/sắp xếp trang.
    @MainActor public func makeViewController(url: URL, onSave: @escaping @MainActor (URL) -> Void) -> UIViewController? {
        guard let document = PDFDocument(url: url), !document.isLocked, document.allowsDocumentChanges,
              document.allowsDocumentAssembly, document.pageCount > 0 else { return nil }
        let tool: UIViewController
        switch self {
        case .crop: tool = PDFCropViewController(document: document, onSave: onSave)
        case .rotate: tool = PDFRotateViewController(document: document, onSave: onSave)
        case .split: tool = PDFSplitViewController(document: document, onSave: onSave)
        case .merge: tool = PDFMergeViewController(document: document, name: url.lastPathComponent, onSave: onSave)
        case .reorder: tool = PDFReorderViewController(document: document, onSave: onSave)
        }
        tool.title = rawValue
        let nav = UINavigationController(rootViewController: tool)
        nav.modalPresentationStyle = .fullScreen
        return nav
    }
}

/// "1-3, 4, 6-8" → [[0, 1, 2], [3], [5, 6, 7]] (chỉ số từ 0). Chuỗi rỗng → mỗi trang một nhóm.
/// nil nếu sai cú pháp hoặc trang nằm ngoài 1...pageCount.
func splitRanges(_ text: String, pageCount: Int) -> [[Int]]? {
    let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard !parts.isEmpty else { return (0..<pageCount).map { [$0] } }
    var groups: [[Int]] = []
    for part in parts {
        let ends = part.split(separator: "-", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard ends.count <= 2, let first = ends[0], let last = ends[ends.count - 1],
              1 <= first, first <= last, last <= pageCount else { return nil }
        groups.append(Array(first - 1...last - 1))
    }
    return groups
}

extension UIViewController {
    func alert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Ghi `document` ra file tạm, dismiss editor rồi báo `onSave`.
    func finish(writing document: PDFDocument, prefix: String, onSave: @escaping @MainActor (URL) -> Void) {
        let url = temporaryPDFURL(prefix)
        guard document.write(to: url) else { return alert("Không ghi được PDF.") }
        dismiss(animated: true) { onSave(url) }
    }

    func addCancelSave(save: Selector, title: String = "Lưu") {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(dismissEditor))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: title, style: .done, target: self, action: save)
    }

    @objc func dismissEditor() { dismiss(animated: true) }
}

/// Toàn bộ trang, cuộn liên tục; dùng cho Rotate và Split.
@MainActor func makePreview(_ document: PDFDocument, in view: UIView) -> PDFView {
    let pdfView = PDFView(frame: view.bounds)
    pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    pdfView.document = document
    pdfView.autoScales = true
    view.addSubview(pdfView)
    return pdfView
}

/// Xoay trang đang xem hoặc cả PDF, bội số 90° qua `PDFPage.rotation` (không render lại nội dung).
final class PDFRotateViewController: UIViewController {
    private let document: PDFDocument
    private let onSave: @MainActor (URL) -> Void
    private var pdfView: PDFView!

    init(document: PDFDocument, onSave: @escaping @MainActor (URL) -> Void) {
        self.document = document
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addCancelSave(save: #selector(save))
        pdfView = makePreview(document, in: view)
        let left = UIBarButtonItem(image: UIImage(systemName: "rotate.left"), primaryAction: UIAction { [weak self] _ in self?.rotateCurrent(by: -90) })
        left.accessibilityLabel = "Xoay trái trang này"
        let right = UIBarButtonItem(image: UIImage(systemName: "rotate.right"), primaryAction: UIAction { [weak self] _ in self?.rotateCurrent(by: 90) })
        right.accessibilityLabel = "Xoay phải trang này"
        let all = UIBarButtonItem(title: "Xoay tất cả 90°", primaryAction: UIAction { [weak self] _ in self?.rotateAll() })
        toolbarItems = [left, right, .flexibleSpace(), all]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
    }

    private func rotateCurrent(by degrees: Int) {
        guard let page = pdfView.currentPage else { return }
        page.rotation += degrees // PDFKit tự chuẩn hóa về 0/90/180/270
        refresh(keeping: page)
    }

    private func rotateAll() {
        let page = pdfView.currentPage
        for index in 0..<document.pageCount { document.page(at: index)?.rotation += 90 }
        refresh(keeping: page)
    }

    private func refresh(keeping page: PDFPage?) {
        pdfView.layoutDocumentView()
        if let page { pdfView.go(to: page) }
    }

    @objc private func save() { finish(writing: document, prefix: "rotate", onSave: onSave) }
}

/// Tách thành nhiều file theo khoảng trang người dùng nhập.
final class PDFSplitViewController: UIViewController {
    private let document: PDFDocument
    private let onSave: @MainActor (URL) -> Void

    init(document: PDFDocument, onSave: @escaping @MainActor (URL) -> Void) {
        self.document = document
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        addCancelSave(save: #selector(askRanges), title: "Tách…")
        _ = makePreview(document, in: view)
    }

    @objc private func askRanges() {
        let prompt = UIAlertController(title: "Tách PDF (\(document.pageCount) trang)",
                                       message: "Mỗi khoảng thành một file, ví dụ: 1-3, 4, 5-8.\nĐể trống: mỗi trang một file.",
                                       preferredStyle: .alert)
        prompt.addTextField { $0.placeholder = "1-3, 4, 5-8" }
        prompt.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        prompt.addAction(UIAlertAction(title: "Tách", style: .default) { [weak self, weak prompt] _ in
            self?.split(prompt?.textFields?.first?.text ?? "")
        })
        present(prompt, animated: true)
    }

    private func split(_ text: String) {
        guard let groups = splitRanges(text, pageCount: document.pageCount) else {
            return alert("Khoảng trang không hợp lệ. Trang phải trong 1–\(document.pageCount), dạng 1-3, 4.")
        }
        var urls: [URL] = []
        for (number, group) in groups.enumerated() {
            let part = PDFDocument()
            for index in group {
                guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
                part.insert(page, at: part.pageCount)
            }
            let url = temporaryPDFURL("split-\(number + 1)")
            guard part.write(to: url) else {
                urls.forEach { try? FileManager.default.removeItem(at: $0) }
                return alert("Không ghi được file thứ \(number + 1).")
            }
            urls.append(url)
        }
        dismiss(animated: true) { [onSave] in urls.forEach(onSave) }
    }
}
