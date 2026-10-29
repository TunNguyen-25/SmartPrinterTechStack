import UIKit
import PDFKit
import PrintFlowKit

/// Kiểm tra converter + page editor rồi thoát:
/// xcrun simctl launch --console booted tuandev.PrintFlowDemo -selftest
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-selftest") else { return }
        runChecks()
        print("SELFTEST OK")
        exit(0)
    }

    private static func runChecks() {
        let sampleFolder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-samples-\(UUID())")
        defer { try? FileManager.default.removeItem(at: sampleFolder) }
        let sampleLibrary = FileLibrary(folder: sampleFolder)
        SampleDocuments.seedIfEmpty(sampleLibrary)
        let samples = sampleLibrary.items().map(\.document)
        check(Set(samples.map { $0.url.lastPathComponent }) == ["mau.pdf", "mau.png", "mau.txt", "anh.jpg"], "đủ 4 file mẫu")
        check(samples.filter { $0.kind == .image }.count == 2, "nhận diện PNG và JPG")
        check(samples.contains { $0.kind == .pdf } && samples.contains { $0.kind == .text }, "nhận diện PDF và TXT")
        do {
            let sample = samples.first { $0.kind == .text }!
            let edited = Data("Đã sửa file mẫu".utf8)
            _ = try sampleLibrary.save(edited, for: sample, mode: .overwrite)
            SampleDocuments.seedIfEmpty(sampleLibrary)
            check(sampleLibrary.items().count == 4, "không seed lại khi đã có file")
            check(try Data(contentsOf: sample.url) == edited, "seed không ghi đè file đã sửa")
            try checkLibrary()
        } catch {
            check(false, "kho file: \(error)")
        }

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

    }

    private static func checkLibrary() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("selftest-\(UUID())")
        defer { try? files.removeItem(at: root) }
        let library = FileLibrary(folder: root.appendingPathComponent("library"))
        check(files.fileExists(atPath: library.folder.path), "tạo thư mục kho file")
        check(PrintFlowContainer(library: library).library === library, "container nhận kho file được inject")
        let source = root.appendingPathComponent("tai-lieu.txt")
        let initial = Data("Nội dung gốc".utf8)
        try initial.write(to: source)
        let original = try library.importFile(at: source)
        check(library.items().count == 1, "import TXT")
        check(original.url.deletingLastPathComponent().path == library.folder.path, "import vào kho")
        check(try Data(contentsOf: source) == initial, "import giữ file nguồn")
        let edited = Data("Nội dung mới".utf8)
        let copy = try library.save(edited, for: original, mode: .newCopy)
        check(library.items().count == 2 && copy.url.lastPathComponent == "tai-lieu (1).txt", "lưu bản mới")
        check(try Data(contentsOf: original.url) == initial, "lưu mới giữ nội dung gốc")
        check(try Data(contentsOf: copy.url) == edited, "lưu mới ghi đúng nội dung")
        let overwritten = try library.save(edited, for: original, mode: .overwrite)
        check(overwritten.url == original.url && library.items().count == 2, "lưu đè giữ URL và số file")
        check(try Data(contentsOf: original.url) == edited, "lưu đè cập nhật nội dung")
        let imported = try library.importFile(at: source)
        check(imported.url.lastPathComponent == "tai-lieu (2).txt" && library.items().count == 3, "import trùng tên tăng hậu tố")
        check(try Data(contentsOf: original.url) == edited, "import trùng không ghi đè")
        let zip = root.appendingPathComponent("test.zip")
        try initial.write(to: zip)
        do {
            _ = try library.importFile(at: zip)
            check(false, "ZIP phải bị từ chối")
        } catch PrintFlowError.unsupported(let url) {
            check(url == zip, "unsupported giữ URL lỗi")
        }
        try initial.write(to: library.folder.appendingPathComponent(".an.txt"))
        try initial.write(to: library.folder.appendingPathComponent("bo-qua.zip"))
        try files.createDirectory(at: library.folder.appendingPathComponent("thu-muc.txt"), withIntermediateDirectories: true)
        let newest = Date(timeIntervalSince1970: 2_000_000_000)
        try files.setAttributes([.modificationDate: newest], ofItemAtPath: copy.url.path)
        let items = library.items()
        check(items.count == 3, "bỏ file ẩn, loại không hỗ trợ và thư mục")
        check(items.first?.document.url == copy.url, "file mới sửa nhất lên đầu")
        check(items.first?.byteCount == edited.count && items.first?.modifiedAt == newest, "metadata ngày sửa và kích thước")
        try library.delete(copy)
        check(library.items().count == 2 && !files.fileExists(atPath: copy.url.path), "xoá file khỏi kho")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("SELFTEST FAIL: \(message)"); exit(1) }
    }
}
