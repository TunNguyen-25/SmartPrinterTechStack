import UIKit

/// Editor TXT: sửa nội dung và lưu UTF-8.
@MainActor
public final class TextFileEditorViewController: UIViewController {
    private var text: String
    let onSave: EditorSaveHandler
    private var hasChanges = false {
        didSet { navigationItem.rightBarButtonItem?.isEnabled = hasChanges }
    }

    init(text: String, onSave: @escaping EditorSaveHandler) {
        self.text = text
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        title = "Sửa văn bản"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Lưu", primaryAction: UIAction { [weak self] _ in self?.save() })
        navigationItem.rightBarButtonItem?.isEnabled = hasChanges
        // TODO: UI — UITextView cập nhật `text` và đặt `hasChanges = true`.
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
        Data(text.utf8)
    }
}
