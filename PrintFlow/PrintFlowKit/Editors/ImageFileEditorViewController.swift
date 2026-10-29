import UIKit
import PDFKit

/// Editor ảnh: crop, xoay, filter. Kết quả ảnh → PDF theo khổ giấy mặc định.
public final class ImageFileEditorViewController: UIViewController {
    private var image: UIImage
    private let imageEditing: ImageEditingService
    private let converter: PDFConverter
    private let settings: PrintSettings
    private let onFinish: (PDFDocument) -> Void

    init(image: UIImage, imageEditing: ImageEditingService, converter: PDFConverter, settings: PrintSettings, onFinish: @escaping (PDFDocument) -> Void) {
        self.image = image
        self.imageEditing = imageEditing
        self.converter = converter
        self.settings = settings
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        title = "Sửa ảnh"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Tiếp", primaryAction: UIAction { [weak self] _ in self?.finish() })
        // TODO: UI — preview ảnh, toolbar xoay/đen trắng gọi imageEditing rồi gán lại `image`.
    }

    private func finish() {
        onFinish(converter.pdf(from: [image], pageSize: settings.pageSize))
    }
}
