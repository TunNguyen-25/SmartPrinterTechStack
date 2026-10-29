import UIKit

/// Editor TXT: sửa nội dung và lưu UTF-8.
@MainActor
public final class TextFileEditorViewController: UIViewController {
    private var text: String
    private var originalText = ""
    let onSave: EditorSaveHandler
    private var hasChanges = false {
        didSet { navigationItem.rightBarButtonItem?.isEnabled = hasChanges }
    }
    let textView = UITextView()

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
        // TODO: Hỏi bỏ thay đổi khi bấm Back mà chưa lưu.

        textView.text = text
        // So với text sau khi UITextView nhận, để gõ rồi xoá về như cũ thì tắt được Lưu.
        originalText = textView.text
        textView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityLabel = "Nội dung văn bản"
        textView.delegate = self
        // Toolbar trên bàn phím: chỉ hiện khi bàn phím mở.
        let toolbar = UIToolbar()
        toolbar.items = [.flexibleSpace(), UIBarButtonItem(title: "Xong", primaryAction: UIAction { [weak self] _ in
            self?.textView.resignFirstResponder()
        })]
        toolbar.sizeToFit()
        textView.inputAccessoryView = toolbar
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            // Bàn phím đóng thì guide trùng safe area; mở thì đẩy text view lên.
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
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

    /// Luôn ghi UTF-8: file gốc dùng encoding khác (UTF-16…) sẽ bị chuyển sang UTF-8 khi lưu.
    func makeData() throws -> Data {
        Data(text.utf8)
    }
}

extension TextFileEditorViewController: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        text = textView.text
        hasChanges = text != originalText
    }
}
