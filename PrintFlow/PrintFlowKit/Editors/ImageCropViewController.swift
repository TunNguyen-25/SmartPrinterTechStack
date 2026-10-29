import UIKit

/// Khung crop trên ảnh; trả về rect chuẩn hoá 0…1 (nil khi Huỷ).
@MainActor
final class ImageCropViewController: UIViewController {
    private let image: UIImage
    private let onFinish: (CGRect?) -> Void
    private let imageView = UIImageView()
    private let overlay = CropOverlayView()
    /// Giữ khung theo toạ độ ảnh để xoay máy không làm mất vùng đã chọn.
    private var normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    init(image: UIImage, onFinish: @escaping (CGRect?) -> Void) {
        self.image = image
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        title = "Cắt ảnh"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Huỷ", primaryAction: UIAction { [weak self] _ in self?.onFinish(nil) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Xong", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.onFinish(self.currentNormalizedRect())
        })
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        // Overlay trùng frame với imageView nên toạ độ của hai view là một.
        for v in [imageView, overlay] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                v.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                v.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                v.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ])
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        normalizedRect = currentNormalizedRect()
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let limit = Self.aspectFitRect(image.size, in: overlay.bounds)
        guard limit != overlay.limit else { return }
        overlay.limit = limit
        overlay.cropRect = CGRect(x: limit.minX + normalizedRect.minX * limit.width, y: limit.minY + normalizedRect.minY * limit.height,
                                  width: normalizedRect.width * limit.width, height: normalizedRect.height * limit.height)
    }

    private func currentNormalizedRect() -> CGRect {
        let limit = overlay.limit, crop = overlay.cropRect
        guard limit.width > 0, limit.height > 0 else { return normalizedRect }
        return CGRect(x: (crop.minX - limit.minX) / limit.width, y: (crop.minY - limit.minY) / limit.height,
                      width: crop.width / limit.width, height: crop.height / limit.height)
    }

    /// Vùng ảnh thật bên trong view `.scaleAspectFit`.
    static func aspectFitRect(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
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
        isAccessibilityElement = true
        accessibilityLabel = "Khung cắt, kéo góc để đổi kích thước"
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let dim = UIBezierPath(rect: bounds)
        dim.append(UIBezierPath(rect: cropRect))
        dim.usesEvenOddFillRule = true
        UIColor.black.withAlphaComponent(0.55).setFill()
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
