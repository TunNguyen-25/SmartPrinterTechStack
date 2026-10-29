import UIKit
import PDFKit
#if DEBUG
@testable import PrintFlowKit
#else
import PrintFlowKit
#endif
import ImageIO
import UniformTypeIdentifiers

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
            #if DEBUG
            try checkEditorSave()
            #endif
            try checkLibrary()
            try checkFileList()
            try checkPrintPipeline()
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

    #if DEBUG
    private static func checkEditorSave() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        for type in [UTType.png, .jpeg] {
            let data = try ImageEditingService.encode(image, as: type)
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            check(decoded.width == 40 && decoded.height == 20, "encode giữ kích thước pixel")
            check(CGImageSourceGetType(source) as String? == type.identifier, "encode đúng định dạng gốc")
        }
        do {
            _ = try ImageEditingService.encode(image, as: .plainText)
            check(false, "định dạng không encode được phải báo lỗi")
        } catch PrintFlowError.cannotEncode {}

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-editor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(folder: root)
        let url = root.appendingPathComponent("goc.txt")
        let initial = Data("Nội dung gốc".utf8)
        let edited = Data("Nội dung mới: tiếng Việt".utf8)
        try initial.write(to: url)
        let document = SourceDocument(url: url)!
        let container = PrintFlowContainer(library: library)
        var saved: SourceDocument?
        let editor = try container.makeEditor(for: document, onSaved: { saved = $0 }) as! TextFileEditorViewController
        editor.loadViewIfNeeded()
        check(editor.navigationItem.rightBarButtonItem?.title == "Lưu", "editor có nút Lưu")
        check(editor.navigationItem.rightBarButtonItem?.isEnabled == false, "chưa sửa thì không lưu")
        try editor.onSave(edited, .newCopy)
        check(library.items().count == 2 && saved?.url.lastPathComponent == "goc (1).txt", "callback lưu bản sao qua container")
        check(try Data(contentsOf: url) == initial, "lưu bản sao giữ gốc")
        check(try Data(contentsOf: saved!.url) == edited, "bản sao giữ UTF-8")
        try editor.onSave(edited, .overwrite)
        check(saved?.url == url && library.items().count == 2, "callback lưu đè giữ URL và số file")
        check(try Data(contentsOf: url) == edited, "callback lưu đè cập nhật gốc")
        let pngURL = root.appendingPathComponent("anh.png")
        try ImageEditingService.encode(image, as: .png).write(to: pngURL)
        let pdfURL = root.appendingPathComponent("trang.pdf")
        try PDFConverter().pdf(from: [image], pageSize: PrintSettings().pageSize).dataRepresentation()!.write(to: pdfURL)
        for url in [pngURL, pdfURL] {
            let editor = try container.makeEditor(for: SourceDocument(url: url)!, onSaved: { _ in })
            editor.loadViewIfNeeded()
            check(editor.navigationItem.rightBarButtonItem?.title == "Lưu" && editor.navigationItem.rightBarButtonItem?.isEnabled == false,
                  "editor ảnh/PDF khoá Lưu khi chưa sửa")
        }
        let navigation = UINavigationController()
        let coordinator = PrintFlowCoordinator(container: container, navigationController: navigation)
        coordinator.start()
        let list = navigation.topViewController as! FileListViewController
        coordinator.open(document)
        let opened = navigation.topViewController as! TextFileEditorViewController
        try opened.onSave(edited, .newCopy)
        check(navigation.topViewController === list, "lưu xong quay về danh sách, không mở Preview")
        list.viewWillAppear(false)
        check(list.tableView.numberOfRows(inSection: 0) == library.items().count, "danh sách reload thấy file mới")
        saved = nil
        try FileManager.default.removeItem(at: root)
        do {
            try editor.onSave(initial, .overwrite)
            check(false, "lưu lỗi phải throw")
        } catch {
            check(saved == nil, "không báo thành công khi ghi file lỗi")
        }
    }

    #endif

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

    private static func checkFileList() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-list-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(folder: root)
        for name in ["A.txt", "B.txt", "C.txt"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        var printed: [URL] = []
        let container = PrintFlowContainer(library: library)
        let list = container.makeFileList(onEdit: { _ in }, onPrint: { printed = $0.map(\.url) })
        list.loadViewIfNeeded()
        list.reload()
        let documents = library.items().map(\.document)
        check(list.tableView.numberOfRows(inSection: 0) == 3, "list đọc kho file")
        let cell = list.tableView(list.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        check((cell.contentConfiguration as? UIListContentConfiguration)?.text == documents[0].url.lastPathComponent, "list hiện tên kèm extension")
        func tap(_ item: UIBarButtonItem?) {
            guard let item, let action = item.action else { check(false, "thiếu action"); return }
            // Self-test chạy trước UIApplication nhận sự kiện, gọi target trực tiếp.
            guard let target = item.target as? NSObject else { check(false, "thiếu target"); return }
            target.perform(action, with: item)
        }
        func select(_ name: String) {
            let row = documents.firstIndex { $0.url.lastPathComponent == name }!
            let path = IndexPath(row: row, section: 0)
            list.tableView.selectRow(at: path, animated: false, scrollPosition: .none)
            list.tableView(list.tableView, didSelectRowAt: path)
        }
        tap(list.navigationItem.rightBarButtonItem)
        check(list.isEditing && list.toolbarItems?.last?.isEnabled == false, "chọn nhiều ban đầu chưa in được")
        select("C.txt"); select("A.txt"); select("B.txt")
        check(list.toolbarItems?.last?.title == "Xem trước in (3)", "đếm file được chọn")
        tap(list.toolbarItems?.last)
        check(printed.map(\.lastPathComponent) == ["C.txt", "A.txt", "B.txt"], "in đúng thứ tự C A B")
        check(!list.isEditing && list.tableView.indexPathsForSelectedRows == nil, "in xong bỏ chọn")
        tap(list.navigationItem.rightBarButtonItem)
        select("C.txt"); select("A.txt")
        let path = IndexPath(row: documents.firstIndex { $0.url.lastPathComponent == "C.txt" }!, section: 0)
        list.tableView.deselectRow(at: path, animated: false)
        list.tableView(list.tableView, didDeselectRowAt: path)
        select("C.txt")
        tap(list.toolbarItems?.last)
        check(printed.map(\.lastPathComponent) == ["A.txt", "C.txt"], "chọn lại được đưa xuống cuối")
        tap(list.navigationItem.rightBarButtonItem)
        select("C.txt")
        tap(list.navigationItem.leftBarButtonItem)
        tap(list.toolbarItems?.last)
        check(printed.first?.lastPathComponent == "C.txt" && Set(printed) == Set(documents.map(\.url)), "chọn tất cả giữ thứ tự trước đó")
        tap(list.navigationItem.rightBarButtonItem)
        tap(list.navigationItem.leftBarButtonItem)
        tap(list.navigationItem.leftBarButtonItem)
        check(list.toolbarItems?.last?.isEnabled == false, "bỏ chọn tất cả tắt nút in")
        select("A.txt")
        let selectedA = documents.first { $0.url.lastPathComponent == "A.txt" }!
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: selectedA.url.path)
        list.reload()
        check(list.tableView.indexPathsForSelectedRows == [IndexPath(row: 0, section: 0)], "reload giữ selection theo URL khi đổi thứ tự")
        try library.delete(documents.first { $0.url.lastPathComponent == "A.txt" }!)
        list.reload()
        check(list.tableView.numberOfRows(inSection: 0) == 2 && list.toolbarItems?.last?.isEnabled == false, "reload bỏ selection file bị xoá")
        for item in library.items() { try library.delete(item.document) }
        list.reload()
        check((list.tableView.backgroundView as? UILabel)?.text == "Chưa có tài liệu. Bấm + để thêm.", "list trống có hướng dẫn import")
        tap(list.navigationItem.rightBarButtonItem)
        let external = root.deletingLastPathComponent().appendingPathComponent("import-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: external) }
        try Data("Nhập từ bên ngoài".utf8).write(to: external)
        list.documentPicker(UIDocumentPickerViewController(forOpeningContentTypes: [.plainText]), didPickDocumentsAt: [external, external])
        check(list.tableView.numberOfRows(inSection: 0) == 2 && library.items().count == 2, "picker import nhiều file kể cả trùng tên")
        let swipe = list.tableView(list.tableView, trailingSwipeActionsConfigurationForRowAt: IndexPath(row: 0, section: 0))!.actions[0]
        var deleted = false
        swipe.handler(swipe, UIView()) { deleted = $0 }
        check(deleted && library.items().count == 1 && list.tableView.numberOfRows(inSection: 0) == 1, "swipe xoá và reload")
        let navigation = UINavigationController()
        let coordinator = PrintFlowCoordinator(container: container, navigationController: navigation)
        coordinator.start()
        check(navigation.viewControllers.first is FileListViewController, "coordinator start bằng file list")
    }

    private static func checkPrintPipeline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-pipeline-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = (1...200).map { "Pipeline dòng \($0)" }.joined(separator: "\n")
        let textURL = root.appendingPathComponent("dau.txt")
        let imageURL = root.appendingPathComponent("giua.png")
        let pdfURL = root.appendingPathComponent("cuoi.pdf")
        try Data(text.utf8).write(to: textURL)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        try image.pngData()!.write(to: imageURL)
        let originalSize = CGSize(width: 300, height: 400)
        let pdfData = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: originalSize)).pdfData { context in
            for label in ["PDF first", "PDF last"] {
                context.beginPage()
                (label as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
        try pdfData.write(to: pdfURL)
        let documents = [textURL, imageURL, pdfURL].map { SourceDocument(url: $0)! }
        let converter = PDFConverter()
        let settings = PrintSettings()
        let textPages = converter.pdf(from: text, style: TextStyle(), pageSize: settings.pageSize).pageCount
        let merged = try converter.pdf(from: documents, settings: settings)
        check(textPages > 1 && merged.pageCount == textPages + 3, "pipeline ghép đủ TXT dài + ảnh + PDF 2 trang")
        check(merged.page(at: 0)?.string?.contains("Pipeline dòng 1") == true, "pipeline bắt đầu bằng TXT")
        check(merged.page(at: textPages - 1)?.string?.contains("Pipeline dòng 200") == true, "pipeline giữ trang TXT cuối")
        check(merged.page(at: textPages)?.bounds(for: .mediaBox).size == settings.pageSize, "pipeline ảnh đúng khổ A4")
        check(merged.page(at: textPages + 1)?.string?.contains("PDF first") == true, "pipeline PDF theo sau ảnh")
        check(merged.page(at: merged.pageCount - 1)?.bounds(for: .mediaBox).size == originalSize, "pipeline giữ khổ PDF gốc")
        let reopened = PDFDocument(data: merged.dataRepresentation()!)!
        check(reopened.page(at: reopened.pageCount - 1)?.string?.contains("PDF last") == true, "pipeline giữ nội dung sau khi nguồn được giải phóng")
        var landscape = settings
        landscape.isLandscape = true
        let horizontal = try converter.pdf(from: [documents[1]], settings: landscape)
        check(horizontal.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 842, height: 595), "pipeline ảnh khổ ngang")
        let thumbnail = horizontal.page(at: 0)!.thumbnail(of: landscape.pageSize, for: .mediaBox)
        check(thumbnail.size.width > thumbnail.size.height, "pipeline ảnh render được sau conversion")
        do {
            _ = try converter.pdf(from: [SourceDocument](), settings: settings)
            check(false, "pipeline phải từ chối danh sách rỗng")
        } catch PrintFlowError.empty {}
        let brokenPDF = root.appendingPathComponent("hong.pdf")
        let brokenImage = root.appendingPathComponent("hong.png")
        let brokenText = root.appendingPathComponent("hong.txt")
        try Data("abc".utf8).write(to: brokenPDF)
        try Data("abc".utf8).write(to: brokenImage)
        try Data([0xFF, 0xFE]).write(to: brokenText)
        let lockedPDF = root.appendingPathComponent("khoa.pdf")
        check(PDFDocument(data: pdfData)!.write(to: lockedPDF, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "owner"]), "tạo PDF khoá")
        let emptyPDF = root.appendingPathComponent("rong.pdf")
        // PDFKit tự thêm trang trắng khi ghi tài liệu rỗng, nên tạo fixture PDF trực tiếp.
        var emptyData = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for object in ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [] /Count 0 >>"] {
            offsets.append(emptyData.count)
            emptyData.append(Data("\(offsets.count) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xref = emptyData.count
        let entries = offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        emptyData.append(Data("xref\n0 3\n0000000000 65535 f \n\(entries)trailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        try emptyData.write(to: emptyPDF)
        check((PDFDocument(url: emptyPDF)?.pageCount ?? 0) == 0, "fixture PDF không chứa trang đọc được")
        for url in [brokenPDF, brokenImage, brokenText, lockedPDF, emptyPDF, root.appendingPathComponent("mat.txt")] {
            do {
                _ = try converter.pdf(from: [documents[0], SourceDocument(url: url)!], settings: settings)
                check(false, "pipeline phải từ chối \(url.lastPathComponent)")
            } catch PrintFlowError.unreadable(let failedURL) {
                check(failedURL == url, "pipeline báo đúng file lỗi")
            }
        }
        let container = PrintFlowContainer(library: FileLibrary(folder: root), defaultSettings: landscape)
        let navigation = UINavigationController(rootViewController: UIViewController())
        let coordinator = PrintFlowCoordinator(container: container, navigationController: navigation)
        for (selection, title) in [(documents, "3 tài liệu"), ([documents[1]], "giua")] {
            let count = navigation.viewControllers.count
            coordinator.showPrintPreview(for: selection)
            check(navigation.view.subviews.last?.subviews.first is UIActivityIndicatorView, "pipeline hiện spinner trước khi convert")
            let deadline = Date(timeIntervalSinceNow: 5)
            while navigation.viewControllers.count == count && Date() < deadline {
                RunLoop.main.run(mode: .default, before: deadline)
            }
            check(navigation.topViewController?.title == title, "Preview đặt tên đúng số file")
            check(!navigation.view.subviews.contains { $0.subviews.first is UIActivityIndicatorView }, "pipeline ẩn spinner sau conversion")
        }
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("SELFTEST FAIL: \(message)"); exit(1) }
    }
}
