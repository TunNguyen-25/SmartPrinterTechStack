import UIKit
import PDFKit
import PencilKit

/// Stack P2: PDFView + PDFAnnotation (highlight, chữ, nét vẽ). Nét vẽ nhập bằng PencilKit rồi chuyển thành ink annotation,
/// nên file xuất ra vẫn là annotation chuẩn PDF (sửa/xóa được ở app khác).
final class PDFAnnotateViewController: UIViewController {
    private let document: PDFDocument
    private let onSave: @MainActor (URL) -> Void
    private let pdfView = PDFView()
    private let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var drawItem: UIBarButtonItem!

    init(document: PDFDocument, onSave: @escaping @MainActor (URL) -> Void) {
        self.document = document
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        title = "PDFKit"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Lưu", style: .done, target: self, action: #selector(save))
        func item(_ label: String, _ symbol: String, _ action: Selector) -> UIBarButtonItem {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol), style: .plain, target: self, action: action)
            item.accessibilityLabel = label
            return item
        }
        drawItem = item("Vẽ", "pencil.tip", #selector(toggleDrawing))
        toolbarItems = [item("Highlight", "highlighter", #selector(highlight)), .flexibleSpace(),
                        item("Thêm chữ", "textformat", #selector(addText)), .flexibleSpace(), drawItem]

        pdfView.document = document
        pdfView.autoScales = true
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isHidden = true
        for v in [pdfView, canvas] as [UIView] {
            v.frame = view.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(v)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
    }

    @objc private func highlight() {
        guard let selection = pdfView.currentSelection, !(selection.string ?? "").isEmpty else {
            return alert("Nhấn giữ để chọn đoạn chữ cần highlight trước.")
        }
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                annotation.color = UIColor.systemYellow.withAlphaComponent(0.5)
                page.addAnnotation(annotation)
            }
        }
        pdfView.clearSelection()
    }

    // ponytail: text đặt ở giữa màn hình, chưa kéo/thả được; thêm gesture di chuyển annotation nếu POC chọn stack này.
    @objc private func addText() {
        let alert = UIAlertController(title: "Thêm chữ", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Nội dung" }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Thêm", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text, !text.isEmpty, let page = pdfView.currentPage else { return }
            let font = UIFont.systemFont(ofSize: 18)
            let size = (text as NSString).size(withAttributes: [.font: font])
            let center = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: page)
            let annotation = PDFAnnotation(bounds: CGRect(x: center.x - size.width / 2 - 4, y: center.y - size.height / 2 - 2,
                                                          width: size.width + 8, height: size.height + 4),
                                           forType: .freeText, withProperties: nil)
            annotation.contents = text
            annotation.font = font
            annotation.fontColor = .systemRed
            annotation.color = .clear
            page.addAnnotation(annotation)
        })
        present(alert, animated: true)
    }

    @objc private func toggleDrawing() {
        let drawing = canvas.isHidden
        if !drawing { commitStrokes() }
        canvas.isHidden = !drawing
        drawItem.accessibilityLabel = drawing ? "Xong vẽ" : "Vẽ"
        drawItem.image = UIImage(systemName: drawing ? "checkmark.circle" : "pencil.tip")
        toolPicker.setVisible(drawing, forFirstResponder: canvas)
        if drawing {
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        } else {
            canvas.resignFirstResponder()
        }
    }

    /// Mỗi stroke PencilKit → 1 ink annotation trên trang chứa điểm đầu của stroke.
    private func commitStrokes() {
        for stroke in canvas.drawing.strokes {
            let points = stroke.path.map { canvas.convert($0.location.applying(stroke.transform), to: pdfView) }
            guard let first = points.first, let page = pdfView.page(for: first, nearest: true) else { continue }
            let pagePoints = points.map { pdfView.convert($0, to: page) }
            // ponytail: annotation phủ cả trang cho đơn giản; tính bounds sát nét nếu cần chọn/xóa từng nét ở app khác.
            let bounds = page.bounds(for: .mediaBox)
            let path = UIBezierPath()
            path.move(to: pagePoints[0])
            pagePoints.dropFirst().forEach { path.addLine(to: $0) }
            path.apply(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            annotation.add(path)
            annotation.color = stroke.ink.color
            let border = PDFBorder()
            border.lineWidth = (stroke.path.first?.size.width ?? 4) / pdfView.scaleFactor
            annotation.border = border
            page.addAnnotation(annotation)
        }
        canvas.drawing = PKDrawing()
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        if !canvas.isHidden { toggleDrawing() }
        let url = temporaryPDFURL("pdfkit")
        guard document.write(to: url) else { return alert("Không ghi được PDF.") }
        dismiss(animated: true) { [onSave] in onSave(url) }
    }

    private func alert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
