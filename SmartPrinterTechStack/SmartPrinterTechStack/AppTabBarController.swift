import UIKit

final class AppTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Library", isDirectory: true)
        let store = DocumentStore(rootURL: root)
        let printer = PrinterViewController(store: store)
        let scan = pendingTool(title: "Scan", detail: "VisionKit / Vision\nScan và OCR sẽ được triển khai ở Task 4. Hiện có thể nhập ảnh hoặc file ở tab File.")
        let files = FilesViewController(store: store)
        viewControllers = zip([printer, scan, files], ["printer", "doc.viewfinder", "folder"]).map { controller, symbol in
            let navigation = UINavigationController(rootViewController: controller)
            navigation.tabBarItem = UITabBarItem(title: controller.title, image: UIImage(systemName: symbol), selectedImage: nil)
            return navigation
        }
    }

    private func pendingTool(title: String, detail: String) -> UIViewController {
        let controller = UIViewController()
        controller.title = title
        controller.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = detail
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: controller.view.readableContentGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: controller.view.readableContentGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.centerYAnchor)
        ])
        return controller
    }
}
