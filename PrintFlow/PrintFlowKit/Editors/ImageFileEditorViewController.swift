import UIKit
import UniformTypeIdentifiers

/// Editor ảnh: xoay, lật, cắt, đen trắng, sáng/tương phản; lưu theo phần mở rộng gốc.
@MainActor
public final class ImageFileEditorViewController: UIViewController {
    private let original: UIImage
    private var image: UIImage {
        didSet { imageView.image = image }
    }
    private let document: SourceDocument
    private let imageEditing: ImageEditingService
    let onSave: EditorSaveHandler
    private var hasChanges = false {
        didSet { navigationItem.rightBarButtonItem?.isEnabled = hasChanges }
    }
    private let imageView = UIImageView()
    private let brightness = UISlider()
    private let contrast = UISlider()
    private lazy var adjustPanel = makeAdjustPanel()
    /// Ảnh nhỏ dùng preview khi kéo slider; nil khi panel đóng.
    private var adjustPreview: UIImage?

    init(image: UIImage, document: SourceDocument, imageEditing: ImageEditingService, onSave: @escaping EditorSaveHandler) {
        // Chuẩn hoá orientation ngay khi mở, nếu không crop/xoay ảnh camera sẽ lệch.
        let upright = ImageEditingService.upright(image)
        self.original = upright
        self.image = upright
        self.document = document
        self.imageEditing = imageEditing
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        title = document.url.lastPathComponent
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Lưu", primaryAction: UIAction { [weak self] _ in self?.save() })
        navigationItem.rightBarButtonItem?.isEnabled = hasChanges
        // TODO: Hỏi bỏ thay đổi khi bấm Back mà chưa lưu.

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .secondarySystemBackground
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Ảnh đang sửa"
        adjustPanel.isHidden = true
        let stack = UIStackView(arrangedSubviews: [imageView, adjustPanel])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        func item(_ symbol: String, _ label: String, _ action: @escaping (ImageFileEditorViewController) -> Void) -> UIBarButtonItem {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                action(self)
            })
            item.accessibilityLabel = label
            return item
        }
        let buttons = [
            item("rotate.right", "Xoay phải") { $0.apply($0.imageEditing.rotateRight) },
            item("arrow.left.and.right.righttriangle.left.righttriangle.right", "Lật ngang") { $0.apply($0.imageEditing.flipHorizontal) },
            item("crop", "Cắt ảnh") { $0.showCrop() },
            item("circle.lefthalf.filled", "Đen trắng") { $0.apply($0.imageEditing.grayscale) },
            item("slider.horizontal.3", "Chỉnh sáng và tương phản") { $0.toggleAdjust() },
            item("arrow.uturn.backward", "Về ảnh gốc") { $0.revert() },
        ]
        toolbarItems = Array(buttons.flatMap { [$0, .flexibleSpace()] }.dropLast())
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    func apply(_ edit: (UIImage) -> UIImage) {
        commitAdjust()
        image = edit(image)
        hasChanges = true
    }

    private func revert() {
        closeAdjustPanel()
        image = original
        hasChanges = false
    }

    private func showCrop() {
        commitAdjust()
        let crop = ImageCropViewController(image: image) { [weak self] rect in
            guard let self else { return }
            if let rect { self.apply { self.imageEditing.crop($0, to: rect) } }
            self.dismiss(animated: true)
        }
        let navigation = UINavigationController(rootViewController: crop)
        // Toàn màn hình để kéo khung không bị nhầm thành vuốt đóng sheet.
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    // MARK: Sáng / tương phản

    private func makeAdjustPanel() -> UIView {
        brightness.minimumValue = -0.5
        brightness.maximumValue = 0.5
        brightness.accessibilityLabel = "Độ sáng"
        contrast.minimumValue = 0.5
        contrast.maximumValue = 1.5
        contrast.accessibilityLabel = "Độ tương phản"
        let rows = [("Sáng", brightness), ("Tương phản", contrast)].map { title, slider -> UIView in
            slider.addAction(UIAction { [weak self] _ in self?.previewAdjust() }, for: .valueChanged)
            let label = UILabel()
            label.text = title
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            label.isAccessibilityElement = false
            label.widthAnchor.constraint(equalToConstant: 96).isActive = true
            let row = UIStackView(arrangedSubviews: [label, slider])
            row.spacing = 12
            return row
        }
        let panel = UIStackView(arrangedSubviews: rows)
        panel.axis = .vertical
        panel.spacing = 8
        panel.isLayoutMarginsRelativeArrangement = true
        panel.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        return panel
    }

    private func toggleAdjust() {
        if adjustPreview == nil {
            adjustPreview = imageEditing.downsampled(image)
            brightness.value = 0
            contrast.value = 1
            adjustPanel.isHidden = false
        } else {
            commitAdjust()
        }
    }

    private func previewAdjust() {
        guard let adjustPreview else { return }
        imageView.image = imageEditing.adjust(adjustPreview, brightness: brightness.value, contrast: contrast.value)
        navigationItem.rightBarButtonItem?.isEnabled = hasChanges || (brightness.value, contrast.value) != (0, 1)
    }

    /// Đóng panel và áp dụng lên ảnh full-size đúng một lần.
    private func commitAdjust() {
        guard adjustPreview != nil else { return }
        let values = (brightness.value, contrast.value)
        closeAdjustPanel()
        if values != (0, 1) { apply { imageEditing.adjust($0, brightness: values.0, contrast: values.1) } }
    }

    private func closeAdjustPanel() {
        adjustPreview = nil
        adjustPanel.isHidden = true
        imageView.image = image
        navigationItem.rightBarButtonItem?.isEnabled = hasChanges
    }

    private func save() {
        commitAdjust()
        SaveOptions.present(from: self, barButtonItem: navigationItem.rightBarButtonItem) { [weak self] mode in
            guard let self else { return }
            do {
                try self.onSave(self.makeData(), mode)
            } catch {
                let alert = UIAlertController(title: "Không lưu được file", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    func makeData() throws -> Data {
        guard let type = UTType(filenameExtension: document.url.pathExtension) else { throw PrintFlowError.cannotEncode }
        return try ImageEditingService.encode(image, as: type)
    }
}
