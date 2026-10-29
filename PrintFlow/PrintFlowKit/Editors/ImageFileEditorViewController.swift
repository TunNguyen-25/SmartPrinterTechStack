import UIKit
import UniformTypeIdentifiers

/// Editor ảnh: lưu theo phần mở rộng gốc.
@MainActor
public final class ImageFileEditorViewController: UIViewController {
    private var image: UIImage
    private let document: SourceDocument
    private let imageEditing: ImageEditingService
    let onSave: EditorSaveHandler
    private var hasChanges = false {
        didSet { navigationItem.rightBarButtonItem?.isEnabled = hasChanges }
    }

    init(image: UIImage, document: SourceDocument, imageEditing: ImageEditingService, onSave: @escaping EditorSaveHandler) {
        self.image = image
        self.document = document
        self.imageEditing = imageEditing
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        title = "Sửa ảnh"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Lưu", primaryAction: UIAction { [weak self] _ in self?.save() })
        navigationItem.rightBarButtonItem?.isEnabled = hasChanges
        // TODO: UI — preview ảnh, xoay/đen trắng qua imageEditing, đặt `hasChanges = true`.
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
        guard let type = UTType(filenameExtension: document.url.pathExtension) else { throw PrintFlowError.cannotEncode }
        return try ImageEditingService.encode(image, as: type)
    }
}
