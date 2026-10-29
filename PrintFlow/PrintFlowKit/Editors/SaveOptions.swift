import UIKit

/// Editor trả dữ liệu đúng định dạng gốc; container chịu trách nhiệm ghi file.
public typealias EditorSaveHandler = (_ data: Data, _ mode: SaveMode) throws -> Void

@MainActor
enum SaveOptions {
    static func present(from viewController: UIViewController, barButtonItem: UIBarButtonItem?, onPick: @escaping (SaveMode) -> Void) {
        let sheet = UIAlertController(title: "Lưu tài liệu", message: "Lưu đè sẽ thay thế file gốc.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Lưu đè", style: .destructive) { _ in onPick(.overwrite) })
        sheet.addAction(UIAlertAction(title: "Lưu thành file mới", style: .default) { _ in onPick(.newCopy) })
        sheet.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            if let barButtonItem {
                popover.barButtonItem = barButtonItem
            } else {
                popover.sourceView = viewController.view
                popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 1, height: 1)
            }
        }
        viewController.present(sheet, animated: true)
    }
}
