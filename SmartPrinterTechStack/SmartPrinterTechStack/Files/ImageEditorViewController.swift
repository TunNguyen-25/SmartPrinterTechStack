import UIKit

final class ImageEditorViewController: UIViewController {
    private let document: LibraryDocument
    private let store: DocumentStore
    private let imageView = UIImageView()
    private var edits = ImageEdits()
    private var previewTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var tools: UIBarButtonItem!

    init(document: LibraryDocument, store: DocumentStore) {
        self.document = document; self.store = store
        super.init(nibName: nil, bundle: nil)
        title = "Sửa ảnh"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel))
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "cancelEditor"
        let save = UIBarButtonItem(title: "Lưu bản sao", style: .done, target: self, action: #selector(save))
        save.accessibilityIdentifier = "saveEditedCopy"
        tools = UIBarButtonItem(title: "Công cụ", menu: nil)
        tools.accessibilityIdentifier = "imageTools"
        navigationItem.rightBarButtonItems = [save, tools]
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Preview chỉnh sửa ảnh"
        imageView.accessibilityIdentifier = "editedImagePreview"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        refresh()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController == nil { previewTask?.cancel(); saveTask?.cancel() }
    }
    @objc private func cancel() { previewTask?.cancel(); saveTask?.cancel(); navigationController?.popViewController(animated: true) }
    private func refresh() {
        tools.menu = UIMenu(children: [
            UIAction(title: "Xoay 90°") { [weak self] _ in self?.edits.quarterTurns += 1; self?.refresh() },
            UIAction(title: "Lật ngang", state: edits.flipHorizontal ? .on : .off) { [weak self] _ in self?.edits.flipHorizontal.toggle(); self?.refresh() },
            UIAction(title: "Lật dọc", state: edits.flipVertical ? .on : .off) { [weak self] _ in self?.edits.flipVertical.toggle(); self?.refresh() },
            UIAction(title: "Crop…") { [weak self] _ in self?.crop() },
            UIAction(title: "Resize…") { [weak self] _ in self?.resize() },
            UIAction(title: "Brightness / Contrast…") { [weak self] _ in self?.colors() },
            UIAction(title: "Grayscale", state: edits.grayscale ? .on : .off) { [weak self] _ in self?.edits.grayscale.toggle(); self?.edits.blackAndWhite = false; self?.refresh() },
            UIAction(title: "B&W", state: edits.blackAndWhite ? .on : .off) { [weak self] _ in self?.edits.blackAndWhite.toggle(); self?.refresh() },
            UIAction(title: "Đặt lại") { [weak self] _ in self?.edits = ImageEdits(); self?.refresh() }
        ])
        previewTask?.cancel()
        let source = document.url, snapshot = edits
        navigationItem.prompt = "Đang tạo preview…"
        navigationItem.rightBarButtonItems?.first?.isEnabled = false
        previewTask = Task {
            do {
                let image = try await ImageEditing.preview(source: source, edits: snapshot)
                try Task.checkCancellation()
                imageView.image = image
                navigationItem.prompt = "Core Image • preview ≤1600px • xuất PNG từ gốc"
                navigationItem.rightBarButtonItems?.first?.isEnabled = true
            } catch is CancellationError {} catch { if !Task.isCancelled { showError(error) } }
        }
    }
    private func crop() {
        let box = edits.crop
        presentEditFields(title: "Crop 0…1, gốc trái trên sau xoay/lật", labels: ["x", "y", "width", "height"], values: [box.minX, box.minY, box.width, box.height]) { [weak self] v in
            let crop = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
            guard crop.width > 0, crop.height > 0, CGRect(x: 0, y: 0, width: 1, height: 1).contains(crop) else { self?.showError(ImageEditing.Failure.invalidEdits); return }
            self?.edits.crop = crop; self?.refresh()
        }
    }
    private func resize() {
        presentEditFields(title: "Kích thước xuất PNG (pixel nguyên)", labels: ["width", "height"], values: [edits.size?.width ?? 1200, edits.size?.height ?? 1600]) { [weak self] v in
            guard v.allSatisfy({ $0 >= 1 && $0.rounded() == $0 }) else { self?.showError(ImageEditing.Failure.invalidEdits); return }
            self?.edits.size = CGSize(width: v[0], height: v[1]); self?.refresh()
        }
    }
    private func colors() {
        presentEditFields(title: "Brightness -1…1 • Contrast 0…4", labels: ["brightness", "contrast"], values: [edits.brightness, edits.contrast]) { [weak self] v in
            guard (-1...1).contains(v[0]), (0...4).contains(v[1]) else { self?.showError(ImageEditing.Failure.invalidEdits); return }
            self?.edits.brightness = v[0]; self?.edits.contrast = v[1]; self?.refresh()
        }
    }
    @objc private func save() {
        guard saveTask == nil else { return }
        previewTask?.cancel()
        navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
        navigationItem.prompt = "Đang xuất PNG từ nguồn… Có thể hủy."
        let source = document.url, snapshot = edits
        saveTask = Task {
            defer { saveTask = nil; navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true } }
            do {
                let output = try await ImageEditing.export(source: source, edits: snapshot)
                defer { try? FileManager.default.removeItem(at: output) }
                try Task.checkCancellation()
                let name = source.deletingPathExtension().lastPathComponent + "-edited.png"
                let saved = try await store.importFile(at: output, preferredName: name)
                guard let nav = navigationController else { return }
                nav.setViewControllers(Array(nav.viewControllers.dropLast(2)) + [DocumentPreviewViewController(document: saved, store: store)], animated: true)
            } catch is CancellationError {} catch { showError(error) }
        }
    }
}

extension UIViewController {
    func presentEditFields(title: String, labels: [String], values: [Double], apply: @escaping ([Double]) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        for (label, value) in zip(labels, values) {
            alert.addTextField { field in
                field.placeholder = label; field.accessibilityLabel = label
                field.font = .preferredFont(forTextStyle: .body)
                field.adjustsFontForContentSizeCategory = true
                let caption = UILabel()
                caption.text = label + ": "
                caption.font = .preferredFont(forTextStyle: .caption1)
                caption.sizeToFit()
                field.leftView = caption; field.leftViewMode = .always
                field.text = String(value); field.keyboardType = .numbersAndPunctuation
                field.clearButtonMode = .always
            }
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Áp dụng", style: .default) { [weak self, weak alert] _ in
            let numbers = alert?.textFields?.compactMap { Double(($0.text ?? "").replacingOccurrences(of: ",", with: ".")) } ?? []
            guard numbers.count == values.count, numbers.allSatisfy(\.isFinite) else { self?.showError(ImageEditing.Failure.invalidEdits); return }
            apply(numbers)
        })
        present(alert, animated: true)
    }
}
