import UIKit
import PrintFlowKit

/// Sinh 3 file mẫu (PDF, ảnh, TXT) vào thư mục tạm để demo không cần import.
enum SampleDocuments {
    static func make() -> [SourceDocument] {
        let folder = FileManager.default.temporaryDirectory
        let text = (1...80).map { "Dòng \($0): Xin chào, đây là file TXT mẫu để thử in." }.joined(separator: "\n")

        let txtURL = folder.appendingPathComponent("mau.txt")
        try? text.write(to: txtURL, atomically: true, encoding: .utf8)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        let pngURL = folder.appendingPathComponent("mau.png")
        try? image.pngData()?.write(to: pngURL)

        let pdfURL = folder.appendingPathComponent("mau.pdf")
        PDFConverter().pdf(from: text, style: TextStyle(), pageSize: PrintSettings().pageSize).write(to: pdfURL)

        return [pdfURL, pngURL, txtURL].compactMap(SourceDocument.init(url:))
    }
}
