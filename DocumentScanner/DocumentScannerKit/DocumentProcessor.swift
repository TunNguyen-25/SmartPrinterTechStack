import UIKit
import Vision
import PDFKit
import CoreImage.CIFilterBuiltins

private let ciContext = CIContext()

/// Bộ lọc màu sau khi scan (Core Image). VisionKit tự áp filter lúc scan; đây là bước làm lại trong app.
public enum ScanFilter: String, CaseIterable, Sendable {
    case original = "Gốc"
    case enhance = "Enhance"
    case grayscale = "Xám"
    case blackWhite = "Đen trắng"

    public func apply(to image: UIImage) -> UIImage {
        guard self != .original, let cgImage = DocumentProcessor.upright(image) else { return image }
        var output = CIImage(cgImage: cgImage)
        if self == .enhance || self == .blackWhite {
            // CIDocumentEnhancer: bỏ bóng, làm trắng nền, tăng tương phản.
            let enhancer = CIFilter.documentEnhancer()
            enhancer.inputImage = output
            enhancer.amount = 1
            output = enhancer.outputImage ?? output
        }
        if self == .grayscale || self == .blackWhite {
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.saturation = 0
            output = controls.outputImage ?? output
        }
        if self == .blackWhite {
            // ponytail: ngưỡng cố định; giấy bóng/đổ bóng mạnh thì cần adaptive threshold.
            let threshold = CIFilter.colorThreshold()
            threshold.inputImage = output
            threshold.threshold = 0.6
            output = threshold.outputImage ?? output
        }
        guard let rendered = ciContext.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: rendered)
    }
}

/// Xử lý ảnh trang scan. Các hàm đồng bộ/nặng: gọi ngoài main thread.
public enum DocumentProcessor {
    /// Ảnh từ Photos có thể mang orientation; Vision/Core Image cần pixel đúng chiều.
    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// Pipeline tự làm (không qua UI VisionKit): tìm mép giấy bằng Vision + nắn phối cảnh bằng Core Image.
    /// nil khi không thấy tài liệu.
    public static func autoCrop(_ image: UIImage) -> UIImage? {
        guard let cgImage = upright(image) else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage)
        let segmentation = VNDetectDocumentSegmentationRequest()
        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.3
        rectangles.minimumSize = 0.3
        try? handler.perform([segmentation, rectangles])
        // Segmentation (ML) không chạy được thì trả cả khung với confidence 0 (gặp trên simulator) → lùi về rectangle (edge-based).
        guard let document = [segmentation.results?.first, rectangles.results?.first]
            .compactMap({ $0 }).first(where: { $0.confidence > 0.5 }) else { return nil }

        // Vision và Core Image cùng gốc tọa độ dưới-trái, chỉ cần đổi normalized → pixel.
        func pixel(_ point: CGPoint) -> CGPoint { VNImagePointForNormalizedPoint(point, cgImage.width, cgImage.height) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: cgImage)
        filter.topLeft = pixel(document.topLeft)
        filter.topRight = pixel(document.topRight)
        filter.bottomLeft = pixel(document.bottomLeft)
        filter.bottomRight = pixel(document.bottomRight)
        guard let output = filter.outputImage, let rendered = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }

    /// Ngôn ngữ OCR mà máy này hỗ trợ (revision mới nhất, mức accurate).
    public static func supportedOCRLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// OCR text thuần (iOS 13+). Ưu tiên tiếng Việt + Anh nếu OS hỗ trợ.
    public static func recognizeText(in image: UIImage) throws -> String {
        guard let cgImage = upright(image) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Vision dùng mã "vi-VT" cho tiếng Việt.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        request.recognitionLanguages = ["vi-VT", "en-US"].filter(supported.contains)
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// iOS 26: đọc cấu trúc tài liệu — tiêu đề, đoạn, bảng, list, barcode, dữ liệu (phone/email/link/ngày/tiền...).
    @available(iOS 26.0, *)
    public static func analyzeStructure(of image: UIImage) async throws -> String {
        guard let cgImage = upright(image) else { return "" }
        var request = RecognizeDocumentsRequest()
        let wanted = ["vi", "en"]
        request.textRecognitionOptions.recognitionLanguages = request.supportedRecognitionLanguages
            .filter { wanted.contains($0.languageCode?.identifier ?? "") }
        guard let document = try await request.perform(on: cgImage).first?.document else { return "Không thấy tài liệu." }

        var lines = ["Đoạn: \(document.paragraphs.count) · Bảng: \(document.tables.count) · List: \(document.lists.count) · Barcode: \(document.barcodes.count)"]
        if let title = document.title { lines.append("Tiêu đề: \(title.transcript)") }
        for (index, table) in document.tables.enumerated() {
            lines.append("\n[Bảng \(index + 1): \(table.rows.count) dòng × \(table.columns.count) cột]")
            lines += table.rows.map { $0.map { $0.content.text.transcript }.joined(separator: " | ") }
        }
        for (index, list) in document.lists.enumerated() {
            lines.append("\n[List \(index + 1)]")
            lines += list.items.map { "\($0.markerString) \($0.itemString)" }
        }
        for barcode in document.barcodes {
            lines.append("\n[Barcode] \(barcode.payloadString ?? "(nhị phân)")")
        }
        // Không import DataDetection (chỉ có từ iOS 26) để app iOS 15 không lỗi link; dùng type qua Vision.
        let detected: [String] = document.text.detectedData.compactMap { data in
            switch data.match.details {
            case .phoneNumber(let phone): return "Phone: \(phone.phoneNumber)"
            case .emailAddress(let email): return "Email: \(email.emailAddress)"
            case .link(let link): return "Link: \(link.url.absoluteString)"
            case .postalAddress(let address): return "Địa chỉ: \(address.fullAddress)"
            case .calendarEvent(let event): return "Ngày: \(event.startDate.map { "\($0)" } ?? "?")"
            case .moneyAmount(let money): return "Tiền: \(money.amount) \(money.currency.identifier)"
            case .shipmentTrackingNumber(let shipment): return "Vận đơn: \(shipment.carrier) \(shipment.trackingNumber)"
            default: return nil
            }
        }
        if !detected.isEmpty {
            lines.append("\n[Dữ liệu nhận diện]")
            lines += detected
        }
        return lines.joined(separator: "\n")
    }

    /// iOS 26: 0...1, càng cao càng có khả năng ống kính bẩn → nhắc người dùng lau camera rồi scan lại.
    @available(iOS 26.0, *)
    public static func smudgeConfidence(of image: UIImage) async throws -> Float {
        guard let cgImage = upright(image) else { return 0 }
        return try await DetectLensSmudgeRequest().perform(on: cgImage).confidence
    }

    /// Ghép trang thành PDF trong thư mục tạm. `searchable`: iOS 16+ để PDFKit tự OCR và nhúng lớp text ẩn.
    public static func makePDF(pages: [UIImage], searchable: Bool) -> URL? {
        let document = PDFDocument()
        for image in pages {
            let page: PDFPage?
            if #available(iOS 16.0, *) {
                // Khổ A4 (dọc/ngang theo ảnh), ảnh aspect-fit — tránh trang PDF to bằng số pixel ảnh.
                let portrait = image.size.height >= image.size.width
                let a4 = portrait ? CGRect(x: 0, y: 0, width: 595, height: 842) : CGRect(x: 0, y: 0, width: 842, height: 595)
                page = PDFPage(image: image, options: [.mediaBox: a4, .upscaleIfSmaller: true])
            } else {
                page = PDFPage(image: image)
            }
            if let page { document.insert(page, at: document.pageCount) }
        }
        var options: [PDFDocumentWriteOption: Any] = [:]
        if #available(iOS 16.0, *), searchable { options[.saveTextFromOCROption] = true }
        if #available(iOS 16.4, *) { options[.saveImagesAsJPEGOption] = true }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Scan-\(UUID().uuidString.prefix(8)).pdf")
        return document.write(to: url, withOptions: options) ? url : nil
    }
}
