import UIKit
import PDFKit
import PrintFlowKit

/// Kiểm tra converter + page editor rồi thoát:
/// xcrun simctl launch --console booted tuandev.PrintFlowDemo -selftest
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-selftest") else { return }
        let samples = SampleDocuments.make()
        check(samples.map(\.kind) == [.pdf, .image, .text], "nhận diện loại file")

        let converter = PDFConverter()
        let a4 = PrintSettings().pageSize
        let textPDF = converter.pdf(from: (1...200).map { "Dòng \($0)" }.joined(separator: "\n"), style: TextStyle(), pageSize: a4)
        check(textPDF.pageCount > 1, "TXT dài phải chia nhiều trang")
        check(textPDF.string?.contains("Dòng 200") == true, "TXT → PDF giữ nội dung")
        check(textPDF.page(at: 0)?.bounds(for: .mediaBox).size == a4, "TXT → PDF đúng khổ A4")

        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { _ in }
        check(converter.pdf(from: [image, image], pageSize: a4).pageCount == 2, "ảnh → PDF mỗi ảnh 1 trang")
        check(ImageEditingService().rotateRight(image).size == CGSize(width: 20, height: 40), "xoay ảnh")

        let editor = PDFPageEditor()
        let pageCount = textPDF.pageCount
        let first = textPDF.page(at: 0)
        editor.rotate(textPDF, pageAt: 0, by: 270)
        editor.rotate(textPDF, pageAt: 0, by: 90)
        check(first?.rotation == 0, "xoay vòng về 0°")
        editor.move(textPDF, from: 0, to: pageCount - 1)
        check(textPDF.page(at: pageCount - 1) == first, "chuyển trang")
        editor.delete(textPDF, pageAt: 0)
        check(textPDF.pageCount == pageCount - 1, "xoá trang")

        print("SELFTEST OK")
        exit(0)
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("SELFTEST FAIL: \(message)"); exit(1) }
    }
}
