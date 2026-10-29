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
            try checkFileList()
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

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { print("SELFTEST FAIL: \(message)"); exit(1) }
    }
}
