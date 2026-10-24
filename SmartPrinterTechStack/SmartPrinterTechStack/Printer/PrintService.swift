import UIKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CoreText

nonisolated enum PrintPaperSize: String, CaseIterable, Sendable {
    case a4 = "A4", letter = "Letter"
    var size: CGSize {
        self == .a4 ? CGSize(width: 210 * 72 / 25.4, height: 297 * 72 / 25.4) : CGSize(width: 612, height: 792)
    }
}

nonisolated enum PrintPreparation {
    enum Failure: Error, LocalizedError {
        case unsupported, corrupt, locked, printingDenied
        var errorDescription: String? {
            switch self {
            case .unsupported: "Chỉ in PDF hoặc ảnh JPEG/PNG/HEIC. Hãy chuyển đổi tài liệu khác thành PDF trước."
            case .corrupt: "Không đọc được nội dung tài liệu hoặc tài liệu không có trang hợp lệ."
            case .locked: "PDF đang khóa. Hãy mở khóa bằng công cụ được phép trước khi in."
            case .printingDenied: "Tài liệu PDF không cho phép in."
            }
        }
    }
    private static func temporaryPDF() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("print-\(UUID().uuidString).pdf")
    }

    @concurrent static func prepare(document: LibraryDocument) async throws -> URL {
        try Task.checkCancellation()
        if document.url.pathExtension.lowercased() != "pdf" {
            guard UTType(filenameExtension: document.url.pathExtension)?.conforms(to: .image) == true else { throw Failure.unsupported }
            return try await imagesPDF(at: [document.url])
        }
        let output = temporaryPDF()
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: output) } }
        try FileManager.default.copyItem(at: document.url, to: output)
        guard let pdf = PDFDocument(url: output) else { throw Failure.corrupt }
        guard !pdf.isLocked else { throw Failure.locked }
        guard pdf.pageCount > 0 else { throw Failure.corrupt }
        guard pdf.allowsPrinting else { throw Failure.printingDenied }
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index), !page.bounds(for: .mediaBox).isEmpty else { throw Failure.corrupt }
        }
        complete = true
        return output
    }

    @concurrent static func imagesPDF(at urls: [URL], paper: PrintPaperSize = .a4) async throws -> URL {
        try Task.checkCancellation()
        guard !urls.isEmpty else { throw Failure.corrupt }
        let output = temporaryPDF()
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: output) } }
        guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
        do {
            for url in urls {
                try Task.checkCancellation()
                try autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let identifier = CGImageSourceGetType(source),
                          [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier].contains(identifier as String),
                          CGImageSourceGetCount(source) == 1 else { throw Failure.unsupported }
                    // shortcut: image print pages use at most 3508 pixels per edge (~300 dpi A4); increase for higher-resolution print requirements.
                    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 3508,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary), CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw Failure.corrupt }
                    let size = image.width > image.height ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size
                    var bounds = CGRect(origin: .zero, size: size)
                    let box = NSData(bytes: &bounds, length: MemoryLayout<CGRect>.size)
                    context.beginPDFPage([kCGPDFContextMediaBox: box] as CFDictionary)
                    context.setFillColor(CGColor(gray: 1, alpha: 1))
                    context.fill(bounds)
                    let area = bounds.insetBy(dx: 18, dy: 18)
                    let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
                    let imageSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                    context.draw(image, in: CGRect(x: bounds.midX - imageSize.width / 2, y: bounds.midY - imageSize.height / 2,
                                                  width: imageSize.width, height: imageSize.height))
                    context.endPDFPage()
                }
            }
            context.closePDF()
        } catch {
            context.closePDF()
            throw error
        }
        try Task.checkCancellation()
        guard PDFDocument(url: output)?.pageCount == urls.count else { throw Failure.corrupt }
        complete = true
        return output
    }

    @concurrent static func calibration(paper: PrintPaperSize) async throws -> URL {
        try Task.checkCancellation()
        let output = temporaryPDF()
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: output) } }
        var bounds = CGRect(origin: .zero, size: paper.size)
        guard let context = CGContext(output as CFURL, mediaBox: &bounds, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(0.5)
        context.stroke(bounds.insetBy(dx: 36, dy: 36))
        let origin = CGPoint(x: 60, y: 160)
        let millimeter = CGFloat(72 / 25.4)
        context.move(to: origin)
        context.addLine(to: CGPoint(x: origin.x + 100 * millimeter, y: origin.y))
        for mm in 0...100 {
            let x = origin.x + CGFloat(mm) * millimeter
            context.move(to: CGPoint(x: x, y: origin.y))
            context.addLine(to: CGPoint(x: x, y: origin.y + (mm % 10 == 0 ? 14 : 7)))
        }
        context.strokePath()
        let lines = ["Calibration \(paper.rawValue)", "100 mm ruler - measure on paper", "Print at 100% / Actual Size; disable Fit to Page.",
                     "Border inset: 0.5 inch. Check clipping, color and duplex on real hardware."]
        for (index, text) in lines.enumerated() {
            context.textPosition = CGPoint(x: 60, y: bounds.height - 90 - CGFloat(index) * 28)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, index == 0 ? 20 : 12, nil)
            ])), context)
        }
        let colors: [[CGFloat]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 0]]
        for (index, components) in colors.enumerated() {
            context.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: components + [1])!)
            context.fill(CGRect(x: 60 + index * 65, y: 220, width: 50, height: 50))
        }
        context.endPDFPage()
        context.closePDF()
        try Task.checkCancellation()
        guard PDFDocument(url: output)?.pageCount == 1 else { throw Failure.corrupt }
        complete = true
        return output
    }
}

@MainActor
final class PrintService: NSObject, UIPrinterPickerControllerDelegate, UIPrintInteractionControllerDelegate {
    static let shared = PrintService()
    static let statusChanged = Notification.Name("PrintServiceStatusChanged")
    private let defaults: UserDefaults
    private(set) var selectedPrinterURL: URL?
    private(set) var status: String {
        didSet { NotificationCenter.default.post(name: Self.statusChanged, object: self) }
    }
    private var busy = false
    private var picker: UIPrinterPickerController?
    private weak var presenter: UIViewController?
    private var jobURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedPrinterURL = defaults.url(forKey: "selectedPrinterURL")
        status = selectedPrinterURL.map { "Đã lưu URL: \($0.absoluteString)\nChưa kiểm tra kết nối; capability chưa xác minh." } ?? "Chưa chọn máy in."
        super.init()
    }

    func choosePrinter(from host: UIViewController) {
        guard !busy, host.viewIfLoaded?.window != nil else { return }
        busy = true
        presenter = host
        let picker = UIPrinterPickerController(initiallySelectedPrinter: selectedPrinterURL.map { UIPrinter(url: $0) })
        self.picker = picker
        picker.delegate = self
        let completion: UIPrinterPickerController.CompletionHandler = { [weak self] picker, selected, error in
            Task { @MainActor in
                guard let self else { return }
                self.picker = nil
                if let error { self.busy = false; self.status = error.localizedDescription; host.showError(error); return }
                guard selected, let printer = picker.selectedPrinter else {
                    self.busy = false
                    self.status = "Đã hủy chọn máy in. URL đã lưu được giữ nguyên; cần kiểm tra lại kết nối."
                    return
                }
                self.selectedPrinterURL = printer.url
                self.defaults.set(printer.url, forKey: "selectedPrinterURL")
                _ = await self.contact(printer)
                self.busy = false
            }
        }
        let shown: Bool
        if host.traitCollection.userInterfaceIdiom == .pad {
            shown = picker.present(from: anchor(in: host), in: host.view, animated: true, completionHandler: completion)
        } else {
            shown = picker.present(animated: true, completionHandler: completion)
        }
        if !shown { self.picker = nil; busy = false; status = "Không mở được picker máy in." }
    }

    func refreshPrinter(from host: UIViewController) {
        guard !busy, let selectedPrinterURL else { return }
        busy = true
        Task {
            _ = await contact(UIPrinter(url: selectedPrinterURL))
            busy = false
        }
    }

    private func contact(_ printer: UIPrinter) async -> Bool {
        status = "Đang liên hệ máy in (có thể mất 30 giây)…\n\(printer.url.absoluteString)"
        let available = await withCheckedContinuation { continuation in
            printer.contactPrinter { available in continuation.resume(returning: available) }
        }
        guard available else {
            status = "Không liên hệ được máy in. Kiểm tra nguồn/mạng rồi thử lại.\n\(printer.url.absoluteString)\nCapability chưa xác minh."
            return false
        }
        status = "\(printer.displayName)\n\(printer.makeAndModel ?? "Không có thông tin model")\n\(printer.url.absoluteString)\nColor: \(printer.supportsColor ? "Có" : "Không") • Duplex: \(printer.supportsDuplex ? "Có" : "Không")\nĐã liên hệ thành công; chưa xác nhận bản giấy."
        return true
    }

    func presentPrint(document: LibraryDocument, from host: UIViewController) {
        start(document: document, from: host, direct: false)
    }

    func presentDirectPrint(document: LibraryDocument, from host: UIViewController) {
        start(document: document, from: host, direct: true)
    }

    private func start(document: LibraryDocument, from host: UIViewController, direct: Bool) {
        guard !busy, host.viewIfLoaded?.window != nil else { return }
        guard UIPrintInteractionController.isPrintingAvailable else {
            host.showError(NSError(domain: "Printing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Hệ thống không hỗ trợ in trên thiết bị này."]))
            return
        }
        busy = true
        status = "Đang kiểm tra nội dung bản in…"
        Task {
            do {
                let url = try await PrintPreparation.prepare(document: document)
                jobURL = url
                guard host.viewIfLoaded?.window != nil, host.presentedViewController == nil else {
                    finish(url: url, message: "Đã hủy mở bản in.")
                    return
                }
                guard UIPrintInteractionController.canPrint(url) else { throw PrintPreparation.Failure.unsupported }
                var printer: UIPrinter?
                if direct {
                    guard let selectedPrinterURL else { throw NSError(domain: "Printing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Chọn máy in ở tab Printer trước khi in trực tiếp."]) }
                    let selected = UIPrinter(url: selectedPrinterURL)
                    guard await contact(selected) else { throw NSError(domain: "Printing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Máy in không phản hồi; chưa gửi lệnh in."]) }
                    guard host.viewIfLoaded?.window != nil, host.presentedViewController == nil else { finish(url: url, message: "Đã hủy in trực tiếp."); return }
                    let confirmed = await confirmDirect(document: document, printer: selected, from: host)
                    guard confirmed else { finish(url: url, message: "Đã hủy in trực tiếp; chưa gửi lệnh."); return }
                    // Recontact after review so stale capabilities are never used for a direct job.
                    guard await contact(selected) else { throw NSError(domain: "Printing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Máy in không còn phản hồi; chưa gửi lệnh in."]) }
                    printer = selected
                }
                let controller = UIPrintInteractionController.shared
                controller.printingItems = nil
                controller.printPageRenderer = nil
                controller.printFormatter = nil
                controller.printingItem = url
                let info = UIPrintInfo(dictionary: nil)
                info.jobName = document.name
                info.outputType = .general
                info.duplex = .none
                controller.printInfo = info
                controller.showsPaperSelectionForLoadedPapers = true
                controller.showsNumberOfCopies = true
                controller.delegate = self
                presenter = host
                let completion: UIPrintInteractionController.CompletionHandler = { [weak self] _, completed, error in
                    Task { @MainActor in
                        guard let self, self.jobURL == url else { return }
                        let message = error.map { "Lỗi in: \($0.localizedDescription)" } ?? (completed
                            ? "UIKit đã hoàn tất xử lý yêu cầu in. Hãy kiểm tra bản giấy; callback không xác nhận giấy đã in."
                            : "Đã hủy yêu cầu in.")
                        self.finish(url: url, message: message)
                        if host.viewIfLoaded?.window != nil, host.presentedViewController == nil {
                            let alert = UIAlertController(title: "Kết quả yêu cầu in", message: message, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
                            host.present(alert, animated: true)
                        }
                    }
                }
                let shown: Bool
                if let printer {
                    shown = controller.print(to: printer, completionHandler: completion)
                } else if host.traitCollection.userInterfaceIdiom == .pad {
                    shown = controller.present(from: anchor(in: host), in: host.view, animated: true, completionHandler: completion)
                } else {
                    shown = controller.present(animated: true, completionHandler: completion)
                }
                if !shown {
                    finish(url: url, message: "Không mở/gửi được yêu cầu in.")
                    host.showError(NSError(domain: "Printing", code: 4, userInfo: [NSLocalizedDescriptionKey: status]))
                }
            } catch {
                if let jobURL { finish(url: jobURL, message: error.localizedDescription) }
                else { busy = false; status = error.localizedDescription }
                if host.viewIfLoaded?.window != nil { host.showError(error) }
            }
        }
    }

    private func confirmDirect(document: LibraryDocument, printer: UIPrinter, from host: UIViewController) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: "Gửi bản in trực tiếp?", message: "\(document.name)\nMáy in: \(printer.displayName)\nDùng mặc định của máy in, không chọn trang/duplex/khổ giấy ở đây. Chọn In qua hệ thống nếu cần chỉnh. Chỉ gửi sau khi bạn đã review toàn bộ tài liệu.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "Gửi lệnh in", style: .default) { _ in continuation.resume(returning: true) })
            host.present(alert, animated: true)
        }
    }

    private func finish(url: URL, message: String) {
        guard jobURL == url else { return }
        UIPrintInteractionController.shared.printingItem = nil
        try? FileManager.default.removeItem(at: url)
        jobURL = nil
        busy = false
        status = message
    }

    private func anchor(in host: UIViewController) -> CGRect {
        CGRect(x: host.view.bounds.midX, y: host.view.safeAreaInsets.top, width: 1, height: 1)
    }
    func printerPickerControllerParentViewController(_ printerPickerController: UIPrinterPickerController) -> UIViewController? { presenter }
    func printInteractionControllerParentViewController(_ printInteractionController: UIPrintInteractionController) -> UIViewController? { presenter }
}
