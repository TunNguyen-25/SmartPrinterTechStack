import UIKit
import PDFKit
import DocumentScannerKit

/// Chạy pipeline trên ảnh mẫu, in kết quả ra console rồi thoát. Không cần camera:
/// xcrun simctl launch --console booted tuandev.DocumentScannerDemo -selftest
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-selftest") else { return }
        Task { // main actor: chỉ là self-check, không cần mượt UI
            let sample = SampleDocument.make()
            guard let cropped = DocumentProcessor.autoCrop(sample) else { fail("autoCrop không thấy tài liệu") }
            print("autoCrop: \(Int(sample.size.width))×\(Int(sample.size.height)) → \(Int(cropped.size.width))×\(Int(cropped.size.height))")

            guard cropped.size.width < sample.size.width * 0.8 else { fail("autoCrop trả gần cả khung, chưa cắt theo mép giấy") }

            let text = (try? DocumentProcessor.recognizeText(in: cropped)) ?? ""
            print("OCR:\n\(text)")
            guard text.localizedCaseInsensitiveContains("hóa đơn") else { fail("OCR không đọc được tiêu đề có dấu") }

            if #available(iOS 26.0, *) {
                let structure = (try? await DocumentProcessor.analyzeStructure(of: cropped)) ?? "(lỗi)"
                print("Cấu trúc:\n\(structure)")
                // Simulator báo internalError; chỉ đo được trên máy thật.
                do { print("Smudge: \(try await DocumentProcessor.smudgeConfidence(of: sample))") } catch { print("Smudge lỗi: \(error)") }
            }

            for filter in ScanFilter.allCases { _ = filter.apply(to: cropped) }
            guard let url = DocumentProcessor.makePDF(pages: [cropped, ScanFilter.blackWhite.apply(to: cropped)], searchable: true),
                  let pdf = PDFDocument(url: url) else { fail("makePDF lỗi") }
            let pdfText = pdf.string ?? ""
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            print("PDF: \(pdf.pageCount) trang, \(size / 1024) KB, text layer \(pdfText.count) ký tự, có 'HÓA ĐƠN': \(pdfText.localizedCaseInsensitiveContains("hóa đơn"))")
            print("SELFTEST OK")
            exit(0)
        }
    }

    private static func fail(_ message: String) -> Never {
        print("SELFTEST FAIL: \(message)")
        exit(1)
    }
}
