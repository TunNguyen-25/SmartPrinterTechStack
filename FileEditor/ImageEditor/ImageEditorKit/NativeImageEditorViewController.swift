import UIKit
import AVFoundation
import CoreImage
import PencilKit

/// Stack native: Core Image (filter, độ sáng, tương phản) + PencilKit (vẽ tay). Không có thư viện ngoài.
final class NativeImageEditorViewController: UIViewController {
    private enum Filter: String, CaseIterable { case none = "Gốc", mono = "Xám", blackWhite = "Đen trắng" }

    private let original: UIImage
    private let preview: CIImage
    private let onFinish: (UIImage?) -> Void
    private let context = CIContext()
    private let imageView = UIImageView()
    private let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var filter = Filter.none
    private var brightness: Float = 0
    private var contrast: Float = 1

    init(image: UIImage, onFinish: @escaping (UIImage?) -> Void) {
        original = Self.upright(image, maxPixel: 4096)
        let cg = original.cgImage!
        let scale = min(1, 1600 / CGFloat(max(cg.width, cg.height)))
        preview = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        title = "Native"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Bỏ EXIF orientation và đưa về scale 1 để pixel ảnh = point khi vẽ.
    // ponytail: giới hạn 4096px cạnh dài — đủ in A4 300dpi; bỏ giới hạn nếu cần in khổ lớn.
    private static func upright(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, maxPixel / max(pixels.width, pixels.height))
        let size = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Xong", style: .done, target: self, action: #selector(done)),
            UIBarButtonItem(image: UIImage(systemName: "pencil.tip.crop.circle"), style: .plain, target: self, action: #selector(toggleDrawing))
        ]

        imageView.contentMode = .scaleAspectFit
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.isUserInteractionEnabled = false

        let filters = UISegmentedControl(items: Filter.allCases.map(\.rawValue))
        filters.selectedSegmentIndex = 0
        filters.addAction(UIAction { [weak self, weak filters] _ in
            guard let self, let filters else { return }
            filter = Filter.allCases[filters.selectedSegmentIndex]
            render()
        }, for: .valueChanged)
        let controls = UIStackView(arrangedSubviews: [
            filters,
            slider("Độ sáng", value: 0, range: -0.5...0.5) { [weak self] in self?.brightness = $0 },
            slider("Tương phản", value: 1, range: 0.5...2) { [weak self] in self?.contrast = $0 }
        ])
        controls.axis = .vertical
        controls.spacing = 12

        for v in [imageView, controls] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        view.addSubview(canvas)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -8),
            imageView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -16),
            controls.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            controls.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16)
        ])
        render()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Canvas phủ đúng vùng ảnh hiển thị; khi xoay màn hình thì scale nét vẽ theo.
        let old = canvas.frame
        let new = AVMakeRect(aspectRatio: original.size, insideRect: imageView.frame)
        guard new != old else { return }
        canvas.frame = new
        if old.width > 0, old.height > 0 {
            canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(scaleX: new.width / old.width, y: new.height / old.height))
        }
    }

    private func slider(_ title: String, value: Float, range: ClosedRange<Float>, onChange: @escaping (Float) -> Void) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.setContentHuggingPriority(.required, for: .horizontal)
        let slider = UISlider()
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.value = value
        slider.accessibilityLabel = title
        slider.addAction(UIAction { [weak self, weak slider] _ in
            guard let slider else { return }
            onChange(slider.value)
            self?.render()
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, slider])
        row.spacing = 12
        return row
    }

    private func filtered(_ input: CIImage) -> CIImage {
        var image = input.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: filter == .none ? 1 : 0,
            kCIInputBrightnessKey: brightness,
            kCIInputContrastKey: contrast
        ])
        if filter == .blackWhite { image = image.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.5]) }
        return image
    }

    // ponytail: render preview đồng bộ trên main thread (~1600px); chuyển sang Task nếu slider bị giật trên máy yếu.
    private func render() {
        let image = filtered(preview)
        imageView.image = context.createCGImage(image, from: image.extent).map { UIImage(cgImage: $0) }
    }

    @objc private func toggleDrawing() {
        let drawing = !canvas.isUserInteractionEnabled
        canvas.isUserInteractionEnabled = drawing
        toolPicker.setVisible(drawing, forFirstResponder: canvas)
        if drawing {
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        } else {
            canvas.resignFirstResponder()
        }
    }

    @objc private func cancel() {
        dismiss(animated: true) { [onFinish] in onFinish(nil) }
    }

    @objc private func done() {
        let size = original.size
        let full = filtered(CIImage(cgImage: original.cgImage!))
        guard let cg = context.createCGImage(full, from: full.extent), canvas.bounds.width > 0 else { return cancel() }
        // Ink đen của PencilKit bị đảo màu ở dark mode; export luôn theo light mode.
        var strokes = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            strokes = canvas.drawing.image(from: canvas.bounds, scale: size.width / canvas.bounds.width)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let result = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
            strokes.draw(in: CGRect(origin: .zero, size: size))
        }
        dismiss(animated: true) { [onFinish] in onFinish(result) }
    }
}
