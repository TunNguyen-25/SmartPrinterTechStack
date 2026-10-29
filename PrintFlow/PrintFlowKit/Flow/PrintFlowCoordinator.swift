import UIKit
import PDFKit

/// Điều hướng: File → Editor theo loại → Print Preview chung → In.
@MainActor
public final class PrintFlowCoordinator {
    private let container: PrintFlowContainer
    private weak var navigationController: UINavigationController?

    public init(container: PrintFlowContainer, navigationController: UINavigationController) {
        self.container = container
        self.navigationController = navigationController
    }

    public func open(_ document: SourceDocument) {
        do {
            let editor = try container.makeEditor(for: document) { [weak self] pdf in
                self?.showPreview(pdf, jobName: document.name)
            }
            navigationController?.pushViewController(editor, animated: true)
        } catch {
            let alert = UIAlertController(title: "Không mở được file", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            navigationController?.present(alert, animated: true)
        }
    }

    public func start() {
        let list = container.makeFileList(onEdit: { [weak self] in self?.open($0) },
                                          onPrint: { [weak self] in self?.showPrintPreview(for: $0) })
        navigationController?.setViewControllers([list], animated: false)
    }

    public func showPrintPreview(for documents: [SourceDocument]) {
        do {
            if let preview = try container.makePreview(for: documents) {
                navigationController?.pushViewController(preview, animated: true)
            }
        } catch {
            let alert = UIAlertController(title: "Không chuyển được sang PDF", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            navigationController?.present(alert, animated: true)
        }
    }

    private func showPreview(_ pdf: PDFDocument, jobName: String) {
        navigationController?.pushViewController(container.makePreview(for: pdf, jobName: jobName), animated: true)
    }
}
