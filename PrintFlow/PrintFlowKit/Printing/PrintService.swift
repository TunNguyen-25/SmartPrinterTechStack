import UIKit
import PDFKit

/// Gửi PDF cuối cùng tới AirPrint. In trực tiếp qua IPP/LAN sau này thêm ở đây.
@MainActor
public final class PrintService {
    public init() {}

    public func print(_ pdf: PDFDocument, settings: PrintSettings, jobName: String, from item: UIBarButtonItem?) {
        let info = UIPrintInfo.printInfo()
        info.jobName = jobName
        info.outputType = settings.grayscale ? .grayscale : .general
        info.orientation = settings.isLandscape ? .landscape : .portrait

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf.dataRepresentation()
        if let item {
            controller.present(from: item, animated: true)
        } else {
            controller.present(animated: true)
        }
    }
}
