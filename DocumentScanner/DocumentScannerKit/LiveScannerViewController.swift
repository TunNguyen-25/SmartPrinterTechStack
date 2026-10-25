import UIKit
import VisionKit

/// DataScanner: highlight text/QR trực tiếp trên camera, chạm để copy; "Chụp" lấy ảnh làm trang (không crop/nắn phối cảnh).
@available(iOS 16.0, *)
final class LiveScannerViewController: UIViewController, DataScannerViewControllerDelegate {
    private let scanner = DataScannerViewController(
        recognizedDataTypes: [.text(), .barcode()],
        qualityLevel: .accurate,
        recognizesMultipleItems: true,
        isHighlightingEnabled: true
    )
    private let label = UILabel()
    private var pages: [UIImage] = []
    private let onFinish: @MainActor ([UIImage]) -> Void

    init(onFinish: @escaping @MainActor ([UIImage]) -> Void) {
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
        scanner.delegate = self

        label.numberOfLines = 4
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.text = "Chạm vào chữ hoặc QR được highlight để copy"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.finish([])
        })
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.finish(self?.pages ?? []) }),
            UIBarButtonItem(image: UIImage(systemName: "camera"), primaryAction: UIAction { [weak self] _ in self?.capture() }),
        ]
        title = "0 trang"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // isAvailable = false khi chưa cấp quyền camera hoặc bị Screen Time chặn.
        guard DataScannerViewController.isAvailable else {
            label.text = "Camera không khả dụng (quyền camera / hạn chế)."
            return
        }
        try? scanner.startScanning()
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
        let text: String
        switch item {
        case .text(let text_): text = text_.transcript
        case .barcode(let barcode): text = barcode.payloadStringValue ?? "(barcode không có payload chữ)"
        @unknown default: return
        }
        UIPasteboard.general.string = text
        label.text = "Đã copy: \(text)"
    }

    private func capture() {
        Task {
            do {
                pages.append(try await scanner.capturePhoto())
                title = "\(pages.count) trang"
            } catch {
                label.text = "Chụp lỗi: \(error.localizedDescription)"
            }
        }
    }

    private func finish(_ pages: [UIImage]) {
        scanner.stopScanning()
        dismiss(animated: true)
        onFinish(pages)
    }
}
