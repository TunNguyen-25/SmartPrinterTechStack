import UIKit
import ZLImageEditor

/// Các tech stack sửa ảnh đang thử. Mỗi engine tự present UI và trả ảnh kết quả (nil = hủy).
public enum ImageEditorEngine: String, CaseIterable, Sendable {
    case native = "Core Image + PencilKit"
    case zlImageEditor = "ZLImageEditor"

    @MainActor public func present(image: UIImage, from parent: UIViewController, completion: @escaping (UIImage?) -> Void) {
        switch self {
        case .native:
            let editor = NativeImageEditorViewController(image: image, onFinish: completion)
            let nav = UINavigationController(rootViewController: editor)
            nav.modalPresentationStyle = .fullScreen
            parent.present(nav, animated: true)
        case .zlImageEditor:
            let config = ZLImageEditorConfiguration.default()
            // .imageSticker cần app tự cung cấp view chọn sticker (ZLImageStickerContainerDelegate) nên chưa bật.
            config.tools = [.draw, .clip, .textSticker, .mosaic, .filter, .adjust]
            ZLEditImageViewController.showEditImageVC(parentVC: parent, image: image,
                                                      completion: { edited, _ in completion(edited) },
                                                      cancelBlock: { completion(nil) })
        }
    }
}
