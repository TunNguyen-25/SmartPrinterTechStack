import UIKit
import PDFKit

/// Editor PDF: sửa trang và lưu PDF.
@MainActor
public final class PDFFileEditorViewController: UIViewController {
    private let pdf: PDFDocument
    private let pageEditor: PDFPageEditor
    let onSave: EditorSaveHandler
    private var hasChanges = false {
        didSet { navigationItem.rightBarButtonItem?.isEnabled = hasChanges }
    }

    init(pdf: PDFDocument, pageEditor: PDFPageEditor, onSave: @escaping EditorSaveHandler) {
        self.pdf = pdf
        self.pageEditor = pageEditor
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        title = "Sửa PDF"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Lưu", primaryAction: UIAction { [weak self] _ in self?.save() })
        navigationItem.rightBarButtonItem?.isEnabled = hasChanges
        // TODO: UI — PDFView + thumbnail, thao tác trang qua pageEditor, đặt `hasChanges = true`.
        // TODO: Hỏi bỏ thay đổi khi bấm Back mà chưa lưu.
    }

    private func save() {
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

    private func makeData() throws -> Data {
        guard let data = pdf.dataRepresentation() else { throw PrintFlowError.cannotEncode }
        return data
    }
}
