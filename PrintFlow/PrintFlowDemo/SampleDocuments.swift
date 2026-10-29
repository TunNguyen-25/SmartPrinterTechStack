import UIKit
import PrintFlowKit

/// Chỉ sinh file mẫu khi kho chưa có tài liệu.
enum SampleDocuments {
    static func seedIfEmpty(_ library: FileLibrary) {
        guard library.items().isEmpty else { return }
        let text = (1...80).map { "Dòng \($0): Xin chào, đây là file TXT mẫu để thử in." }.joined(separator: "\n")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
        let directionalImage = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 160))
            ("TOP ↑" as NSString).draw(at: CGPoint(x: 140, y: 40), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 64), .foregroundColor: UIColor.black
            ])
        }
        do {
            guard let png = image.pngData(), let jpg = directionalImage.jpegData(compressionQuality: 0.9),
                  let pdf = PDFConverter().pdf(from: text, style: TextStyle(), pageSize: PrintSettings().pageSize).dataRepresentation() else {
                throw CocoaError(.fileWriteUnknown)
            }
            for (name, data) in [("mau.pdf", pdf), ("mau.png", png), ("mau.txt", Data(text.utf8)), ("anh.jpg", jpg)] {
                let document = SourceDocument(url: library.folder.appendingPathComponent(name))!
                _ = try library.save(data, for: document, mode: .newCopy)
            }
        } catch {
            print("Không tạo được file mẫu: \(error.localizedDescription)")
        }
    }
}
