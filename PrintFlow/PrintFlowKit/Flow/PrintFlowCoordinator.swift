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
        guard let navigationController else { return }
        let overlay = UIView(frame: navigationController.view.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .systemBackground.withAlphaComponent(0.8)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        spinner.accessibilityLabel = "Đang chuyển sang PDF"
        overlay.addSubview(spinner)
        navigationController.view.addSubview(overlay)
        spinner.startAnimating()
        // Nhường một vòng runloop để spinner kịp vẽ trước khi convert trên main.
        DispatchQueue.main.async { [weak self] in
            guard let self else { overlay.removeFromSuperview(); return }
            do {
                let preview = try self.container.makePreview(for: documents)
                overlay.removeFromSuperview()
                navigationController.pushViewController(preview, animated: true)
            } catch {
                overlay.removeFromSuperview()
                let alert = UIAlertController(title: "Không chuyển được sang PDF", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                navigationController.present(alert, animated: true)
            }
        }
    }

    private func showPreview(_ pdf: PDFDocument, jobName: String) {
        navigationController?.pushViewController(container.makePreview(for: pdf, jobName: jobName), animated: true)
    }
}
