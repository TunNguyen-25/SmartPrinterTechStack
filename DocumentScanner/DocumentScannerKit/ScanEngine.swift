import UIKit
import VisionKit

/// Các cách scan bằng camera đang thử. Mỗi engine tự present UI và trả ảnh từng trang (rỗng = hủy/lỗi).
public enum ScanEngine: String, CaseIterable, Sendable {
    case documentCamera = "VisionKit Document Camera"
    case dataScanner = "VisionKit DataScanner (live text/QR, iOS 16+)"

    /// Simulator luôn false: cả hai cần camera thật (DataScanner còn cần chip A12+).
    @MainActor public var isAvailable: Bool {
        switch self {
        case .documentCamera: return VNDocumentCameraViewController.isSupported
        case .dataScanner:
            guard #available(iOS 16.0, *) else { return false }
            return DataScannerViewController.isSupported
        }
    }

    @MainActor public func present(from parent: UIViewController, completion: @escaping @MainActor ([UIImage]) -> Void) {
        switch self {
        case .documentCamera:
            let camera = VNDocumentCameraViewController()
            let delegate = DocumentCameraDelegate(completion: completion) // tự giữ mình, xem keepAlive
            camera.delegate = delegate
            parent.present(camera, animated: true)
        case .dataScanner:
            guard #available(iOS 16.0, *) else { return completion([]) }
            let nav = UINavigationController(rootViewController: LiveScannerViewController(onFinish: completion))
            nav.modalPresentationStyle = .fullScreen
            parent.present(nav, animated: true)
        }
    }
}

/// VNDocumentCameraViewController giữ delegate weak, nên object tự giữ mình tới khi camera đóng.
@MainActor private final class DocumentCameraDelegate: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
    private let completion: @MainActor ([UIImage]) -> Void
    private var keepAlive: DocumentCameraDelegate?

    init(completion: @escaping @MainActor ([UIImage]) -> Void) {
        self.completion = completion
        super.init()
        keepAlive = self
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        // Ảnh đã được VisionKit crop + nắn phối cảnh; ponytail: giữ hết trang trong RAM, scan 30+ trang thì ghi ra đĩa từng trang.
        finish(controller, (0..<scan.pageCount).map(scan.imageOfPage(at:)))
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        finish(controller, [])
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        print("Document camera lỗi:", error)
        finish(controller, [])
    }

    private func finish(_ controller: VNDocumentCameraViewController, _ pages: [UIImage]) {
        controller.dismiss(animated: true)
        completion(pages)
        keepAlive = nil
    }
}
