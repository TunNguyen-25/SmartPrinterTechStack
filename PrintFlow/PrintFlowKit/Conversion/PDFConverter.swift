import UIKit
import PDFKit
import AVFoundation
import ImageIO

public struct TextStyle: Sendable, Equatable {
    public var fontSize: CGFloat = 12
    public var margin: CGFloat = 36

    public init() {}
    public var font: UIFont { .systemFont(ofSize: fontSize) }
}

/// Chuyển tài liệu thành PDF chung trước khi xem trước in.
@MainActor
public final class PDFConverter {
    public init() {}

    /// Ghép nhiều file thành một PDF theo thứ tự truyền vào.
    public func pdf(from documents: [SourceDocument], settings: PrintSettings) throws -> PDFDocument {
        guard !documents.isEmpty else { throw PrintFlowError.empty }
        let result = PDFDocument()
        var sources: [PDFDocument] = []
        for document in documents {
            try autoreleasepool {
                let source: PDFDocument
                switch document.kind {
                case .pdf:
                    guard let pdf = PDFDocument(url: document.url), !pdf.isLocked, pdf.pageCount > 0 else {
                        throw PrintFlowError.unreadable(document.url)
                    }
                    source = pdf
                case .image:
                    // ponytail: 3000px ≈ 300dpi cho A4, tăng nếu in khổ lớn
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 3000,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ]
                    guard let imageSource = CGImageSourceCreateWithURL(document.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                        throw PrintFlowError.unreadable(document.url)
                    }
                    let image = UIImage(cgImage: thumbnail)
                    let paper = CGRect(origin: .zero, size: settings.pageSize)
                    let data = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
                        context.beginPage()
                        image.draw(in: AVMakeRect(aspectRatio: image.size, insideRect: paper.insetBy(dx: 18, dy: 18)))
                    }
                    guard let pdf = PDFDocument(data: data) else { throw PrintFlowError.unreadable(document.url) }
                    source = pdf
                case .text:
                    guard let text = try? String(contentsOf: document.url, encoding: .utf8) else {
                        throw PrintFlowError.unreadable(document.url)
                    }
                    source = pdf(from: text, style: TextStyle(), pageSize: settings.pageSize)
                }
                sources.append(source)
                for index in 0..<source.pageCount {
                    guard let page = source.page(at: index)?.copy() as? PDFPage else {
                        throw PrintFlowError.unreadable(document.url)
                    }
                    result.insert(page, at: result.pageCount)
                }
            }
        }
        // PDFKit cần giữ nguồn đến khi serialize xong; PDF trả về tự sở hữu dữ liệu.
        let data = withExtendedLifetime(sources) { result.dataRepresentation() }
        guard let data, let pdf = PDFDocument(data: data) else {
            throw PrintFlowError.unreadable(documents[documents.count - 1].url)
        }
        return pdf
    }

    /// Mỗi ảnh một trang, aspect-fit, căn giữa.
    public func pdf(from images: [UIImage], pageSize: CGSize) -> PDFDocument {
        let bounds = CGRect(origin: .zero, size: pageSize)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for image in images {
                context.beginPage()
                image.draw(in: AVMakeRect(aspectRatio: image.size, insideRect: bounds))
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }

    /// Dùng formatter của hệ thống để tự ngắt dòng và chia trang.
    public func pdf(from text: String, style: TextStyle, pageSize: CGSize) -> PDFDocument {
        let formatter = UISimpleTextPrintFormatter(text: text)
        formatter.font = style.font
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paper = CGRect(origin: .zero, size: pageSize)
        // ponytail: paperRect/printableRect chỉ đọc được, KVC là cách phổ biến để render offline.
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.insetBy(dx: style.margin, dy: style.margin), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return PDFDocument(data: data as Data) ?? PDFDocument()
    }
}
