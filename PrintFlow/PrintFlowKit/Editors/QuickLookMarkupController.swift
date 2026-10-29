import QuickLook

/// Dùng nguyên bộ Markup của hệ thống, app không tự viết UI ghi chú/ký.
@MainActor
final class QuickLookMarkupController: QLPreviewController, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private let url: URL
    private let onSave: @MainActor (URL) -> Void

    init(url: URL, onSave: @escaping @MainActor (URL) -> Void) {
        self.url = url
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        dataSource = self
        delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    // QLPreviewControllerDelegate không gắn MainActor (có thể gọi ngoài main thread) nên các hàm là nonisolated.
    nonisolated func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode { .createCopy }

    // Có thể được gọi cả sau khi đã dismiss, nên báo qua onSave thay vì chờ dismiss.
    nonisolated func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem, at modifiedContentsURL: URL) {
        // File của Quick Look có thể bị dọn ngay; copy ra trước. PDFDocument đọc file lười nên bản copy phải còn đến khi lưu.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("markup-\(UUID()).pdf")
        guard (try? FileManager.default.copyItem(at: modifiedContentsURL, to: copy)) != nil else { return }
        let onSave = onSave
        Task { @MainActor in onSave(copy) }
    }
}
