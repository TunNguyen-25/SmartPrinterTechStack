import UIKit
import PDFKit
import AVFoundation

public struct TextStyle: Sendable, Equatable {
    public var fontSize: CGFloat = 12
    public var margin: CGFloat = 36

    public init() {}
    public var font: UIFont { .systemFont(ofSize: fontSize) }
}

/// Điểm hội tụ của flow: mỗi editor gọi converter để ra PDF rồi chuyển sang Print Preview.
@MainActor
public final class PDFConverter {
    public init() {}

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
