import UIKit
import PDFKit

/// Crop bằng khung kéo trên từng trang → `setBounds(_:for: .cropBox)`.
/// Chỉ ẩn phần ngoài khung, nội dung vẫn nằm trong file (không phải redaction).
final class PDFCropViewController: UIViewController {
    private let document: PDFDocument
    private let onSave: @MainActor (URL) -> Void
    private let pdfView = PDFView()
    private let overlay = CropOverlayView()

    init(document: PDFDocument, onSave: @escaping @MainActor (URL) -> Void) {
        self.document = document
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        addCancelSave(save: #selector(save))
        let previous = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), primaryAction: UIAction { [weak self] _ in self?.pdfView.goToPreviousPage(nil) })
        previous.accessibilityLabel = "Trang trước"
        let next = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), primaryAction: UIAction { [weak self] _ in self?.pdfView.goToNextPage(nil) })
        next.accessibilityLabel = "Trang sau"
        toolbarItems = [previous, .flexibleSpace(),
                        UIBarButtonItem(title: "Crop trang này", primaryAction: UIAction { [weak self] _ in self?.crop(all: false) }),
                        UIBarButtonItem(title: "Crop tất cả", primaryAction: UIAction { [weak self] _ in self?.crop(all: true) }),
                        .flexibleSpace(), next]

        pdfView.document = document
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        // Overlay trùng frame với pdfView nên tọa độ của hai view là một.
        for v in [pdfView, overlay] as [UIView] {
            v.frame = view.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(v)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(resetOverlay), name: .PDFViewPageChanged, object: pdfView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
    }

    // ponytail: mỗi lần layout (xoay máy, hiện toolbar) khung crop về lại cả trang; giữ tỉ lệ khung nếu cần.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resetOverlay()
    }

    @objc private func resetOverlay() {
        pdfView.layoutIfNeeded()
        guard let page = pdfView.currentPage else { return }
        title = "Crop \(document.index(for: page) + 1)/\(document.pageCount)"
        let pageRect = pdfView.convert(page.bounds(for: .cropBox), from: page)
        overlay.limit = pageRect
        overlay.cropRect = pageRect
    }

    /// Đổi khung trên màn hình sang tọa độ trang (đã tính rotation), rồi cắt theo media box của từng trang.
    private func crop(all: Bool) {
        guard let current = pdfView.currentPage else { return }
        let box = pdfView.convert(overlay.cropRect, to: current)
        let pages = all ? (0..<document.pageCount).compactMap(document.page(at:)) : [current]
        for page in pages {
            let rect = box.intersection(page.bounds(for: .mediaBox))
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { continue }
            page.setBounds(rect, for: .cropBox)
        }
        pdfView.layoutDocumentView()
        resetOverlay()
    }

    @objc private func save() { finish(writing: document, prefix: "crop", onSave: onSave) }
}

/// Khung crop: kéo gần góc để đổi kích thước, kéo chỗ khác để di chuyển; luôn nằm trong `limit`.
private final class CropOverlayView: UIView {
    var limit = CGRect.zero
    var cropRect = CGRect.zero { didSet { setNeedsDisplay() } }
    private var start = CGRect.zero
    private var corner: (left: Bool, top: Bool)?
    private let minSize: CGFloat = 30

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let dim = UIBezierPath(rect: bounds)
        dim.append(UIBezierPath(rect: cropRect))
        dim.usesEvenOddFillRule = true
        UIColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()
        UIColor.systemYellow.set()
        let border = UIBezierPath(rect: cropRect)
        border.lineWidth = 2
        border.stroke()
        for x in [cropRect.minX, cropRect.maxX] {
            for y in [cropRect.minY, cropRect.maxY] {
                UIBezierPath(ovalIn: CGRect(x: x - 8, y: y - 8, width: 16, height: 16)).fill()
            }
        }
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            start = cropRect
            let p = gesture.location(in: self)
            corner = [(left: true, top: true), (left: false, top: true), (left: true, top: false), (left: false, top: false)].first {
                hypot(($0.left ? start.minX : start.maxX) - p.x, ($0.top ? start.minY : start.maxY) - p.y) < 44
            }
        case .changed:
            let t = gesture.translation(in: self)
            if let corner {
                var (x0, y0, x1, y1) = (start.minX, start.minY, start.maxX, start.maxY)
                if corner.left { x0 = min(max(x0 + t.x, limit.minX), x1 - minSize) } else { x1 = max(min(x1 + t.x, limit.maxX), x0 + minSize) }
                if corner.top { y0 = min(max(y0 + t.y, limit.minY), y1 - minSize) } else { y1 = max(min(y1 + t.y, limit.maxY), y0 + minSize) }
                cropRect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            } else {
                var moved = start.offsetBy(dx: t.x, dy: t.y)
                moved.origin.x = min(max(moved.minX, limit.minX), limit.maxX - moved.width)
                moved.origin.y = min(max(moved.minY, limit.minY), limit.maxY - moved.height)
                cropRect = moved
            }
        default:
            break
        }
    }
}
