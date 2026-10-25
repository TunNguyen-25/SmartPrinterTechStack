import UIKit

final class FilesViewController: UITableViewController, UISearchResultsUpdating {
    private let store: DocumentStore
    private var documents: [LibraryDocument] = []
    private let search = UISearchController(searchResultsController: nil)
    private var visible: [LibraryDocument] {
        let query = search.searchBar.text ?? ""
        return query.isEmpty ? documents : documents.filter { $0.name.localizedStandardContains(query) }
    }

    init(store: DocumentStore) {
        self.store = store
        super.init(style: .insetGrouped)
        title = "File"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Tìm theo tên"
        navigationItem.searchController = search
        definesPresentationContext = true
        let actions = [
            importAction("Files", identifier: "importFiles", source: .files),
            importAction("Photos", identifier: "importPhotos", source: .photos),
            importAction("PDF mẫu offline", identifier: "samplePDF", source: .sample("pdf")),
            importAction("Ảnh mẫu offline", identifier: "sampleImage", source: .sample("png")),
            importAction("Text mẫu offline", identifier: "sampleText", source: .sample("txt"))
        ]
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), menu: UIMenu(children: actions))
        add.accessibilityLabel = "Nhập tài liệu"
        add.accessibilityIdentifier = "importDocuments"
        navigationItem.rightBarButtonItem = add
    }

    private func importAction(_ title: String, identifier: String, source: ImportViewController.Source) -> UIAction {
        let action = UIAction(title: title) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(ImportViewController(store: self.store, source: source), animated: true)
        }
        action.accessibilityIdentifier = identifier
        return action
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            do {
                documents = try await store.list()
                tableView.reloadData()
                let label = UILabel()
                label.text = "Chưa có tài liệu. Bấm + để nhập.\nFiles / Photos • lưu local • iOS 15+"
                label.font = .preferredFont(forTextStyle: .body)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .secondaryLabel
                label.numberOfLines = 0
                label.textAlignment = .center
                tableView.backgroundView = documents.isEmpty ? label : nil
            } catch { showError(error) }
        }
    }

    func updateSearchResults(for searchController: UISearchController) { tableView.reloadData() }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visible.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "document") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "document")
        let document = visible[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = document.name
        content.textProperties.numberOfLines = 0
        content.secondaryText = document.url.pathExtension.uppercased()
        content.image = UIImage(systemName: "doc")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = document.url.absoluteString
        Task { [weak cell] in
            let summary = await DocumentThumbnailCache.shared.summary(for: document)
            guard let cell, cell.accessibilityIdentifier == document.url.absoluteString else { return }
            var updated = cell.defaultContentConfiguration()
            updated.text = document.name
            updated.textProperties.numberOfLines = 0
            updated.secondaryText = summary.detail
            updated.image = summary.image ?? UIImage(systemName: "doc")
            updated.imageProperties.maximumSize = CGSize(width: 48, height: 60)
            cell.contentConfiguration = updated
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let document = visible[indexPath.row]
        navigationController?.pushViewController(DocumentPreviewViewController(document: document, store: store), animated: true)
    }
}

extension UIViewController {
    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Không thể hoàn tất", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        present(alert, animated: true)
    }
}
