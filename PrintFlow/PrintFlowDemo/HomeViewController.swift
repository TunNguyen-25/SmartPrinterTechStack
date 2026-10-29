import UIKit
import PrintFlowKit

/// Màn chọn file. Bản thật sẽ là thư viện file / document picker; giờ chỉ có menu file mẫu.
final class HomeViewController: UIViewController {
    private let samples: [SourceDocument]
    private let onPick: (SourceDocument) -> Void

    init(samples: [SourceDocument], onPick: @escaping (SourceDocument) -> Void) {
        self.samples = samples
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        title = "Print Flow"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let actions = samples.map { sample in
            UIAction(title: sample.url.lastPathComponent) { [weak self] _ in self?.onPick(sample) }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Mở file mẫu", menu: UIMenu(children: actions))
        // TODO: UI — danh sách file, nút import.
    }
}
