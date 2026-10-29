import UIKit
import PDFKit

/// Editor TXT: sửa nội dung, cỡ chữ, lề. Kết quả text → PDF theo khổ giấy mặc định.
public final class TextFileEditorViewController: UIViewController {
    private var text: String
    private var style = TextStyle()
    private let converter: PDFConverter
    private let settings: PrintSettings
    private let onFinish: (PDFDocument) -> Void

    init(text: String, converter: PDFConverter, settings: PrintSettings, onFinish: @escaping (PDFDocument) -> Void) {
        self.text = text
        self.converter = converter
        self.settings = settings
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        title = "Sửa văn bản"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Tiếp", primaryAction: UIAction { [weak self] _ in self?.finish() })
        // TODO: UI — UITextView bind vào `text`, stepper cỡ chữ/lề bind vào `style`.
    }

    private func finish() {
        onFinish(converter.pdf(from: text, style: style, pageSize: settings.pageSize))
    }
}
