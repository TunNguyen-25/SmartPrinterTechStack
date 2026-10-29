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

    private func showPreview(_ pdf: PDFDocument, jobName: String) {
        navigationController?.pushViewController(container.makePreview(for: pdf, jobName: jobName), animated: true)
    }
}
