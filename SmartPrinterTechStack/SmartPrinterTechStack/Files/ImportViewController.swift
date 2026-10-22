import PhotosUI
import UniformTypeIdentifiers
import UIKit

final class ImportViewController: UITableViewController, UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
    enum Source { case files, photos, sample(String) }
    private let store: DocumentStore
    private let source: Source
    private var started = false
    private var results: [String] = []
    private var operation: Task<Void, Never>?
    private var providerProgress: Progress?

    init(store: DocumentStore, source: Source) {
        self.store = store
        self.source = source
        super.init(style: .insetGrouped)
        title = "Nhập tài liệu"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        switch source {
        case .files:
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
            picker.allowsMultipleSelection = true
            picker.delegate = self
            present(picker, animated: true)
        case .photos:
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            configuration.selectionLimit = 0
            configuration.selection = .ordered
            configuration.preferredAssetRepresentationMode = .current
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            present(picker, animated: true)
        case .sample(let ext):
            guard let url = Bundle.main.url(forResource: "Sample", withExtension: ext) else {
                finish(error: CocoaError(.fileNoSuchFile))
                return
            }
            importURLs([url])
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importURLs(urls)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done() }

    private func importURLs(_ urls: [URL]) {
        // Keep provider access alive from this delegate callback until the durable copy finishes.
        let scopes = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        operation = Task {
            defer { for (url, scoped) in scopes where scoped { url.stopAccessingSecurityScopedResource() } }
            for (index, url) in urls.enumerated() {
                guard !Task.isCancelled else { break }
                navigationItem.prompt = "Đang nhập \(index + 1)/\(urls.count)…"
                do {
                    let document = try await store.importFile(at: url, preferredName: nil)
                    results.append("Đã nhập: \(document.name)")
                } catch {
                    results.append("\(url.lastPathComponent): \(error is CancellationError ? "Đã hủy" : error.localizedDescription)")
                }
                tableView.reloadData()
            }
            finish()
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking selections: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !selections.isEmpty else { done(); return }
        operation = Task {
            for (index, result) in selections.enumerated() {
                guard !Task.isCancelled else { break }
                navigationItem.prompt = "Đang nhập ảnh \(index + 1)/\(selections.count)…"
                do {
                    let staged = try await stagePhoto(result.itemProvider)
                    defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
                    try Task.checkCancellation()
                    let document = try await store.importFile(at: staged, preferredName: nil)
                    results.append("Đã nhập: \(document.name)")
                } catch {
                    results.append("Ảnh \(index + 1): \(error is CancellationError ? "Đã hủy" : error.localizedDescription)")
                }
                providerProgress = nil
                tableView.reloadData()
            }
            finish()
        }
    }

    private func stagePhoto(_ provider: NSItemProvider) async throws -> URL {
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
            throw CocoaError(.fileReadUnknown)
        }
        return try await withCheckedThrowingContinuation { continuation in
            providerProgress = provider.loadFileRepresentation(forTypeIdentifier: type) { @Sendable url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw CocoaError(.fileNoSuchFile) }
                    // The supplied URL expires when this callback returns: copy synchronously here.
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let copy = folder.appendingPathComponent(url.lastPathComponent)
                    do { try FileManager.default.copyItem(at: url, to: copy) }
                    catch { try? FileManager.default.removeItem(at: folder); throw error }
                    continuation.resume(returning: copy)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    @objc private func cancel() {
        operation?.cancel()
        providerProgress?.cancel()
        navigationItem.prompt = "Đang hủy; tài liệu đã lưu được giữ lại…"
        if operation == nil { done() }
    }
    private func finish(error: Error? = nil) {
        if let error { results.append(error.localizedDescription) }
        navigationItem.prompt = Task.isCancelled ? "Đã hủy • giữ các file đã lưu" : "Hoàn tất • Files / PhotosUI"
        navigationItem.leftBarButtonItem = nil
        let finish = UIBarButtonItem(title: "Xong", style: .done, target: self, action: #selector(done))
        finish.accessibilityIdentifier = "finishImport"
        navigationItem.rightBarButtonItem = finish
        operation = nil
        tableView.reloadData()
    }
    @objc private func done() { navigationController?.popViewController(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = results[indexPath.row]
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }
}
