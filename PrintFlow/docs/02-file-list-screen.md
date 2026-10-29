# Task 02 — Màn danh sách file

> Cần task 01. Đọc [00-README.md](00-README.md) trước.

## Mục tiêu
Đây là màn gốc của app. Màn này hiển thị các file trong `FileLibrary`, cho phép mở **Sửa** hoặc **Xem trước in** cho một file, và **chọn nhiều** file để xem trước in chung.

## Việc cần làm

### 1. `PrintFlowKit/Library/FileListViewController.swift` (mới)

```swift
public final class FileListViewController: UITableViewController {
    init(library: FileLibrary,
         onEdit: @escaping (SourceDocument) -> Void,
         onPrint: @escaping ([SourceDocument]) -> Void)
    public func reload()      // đọc lại library.items() rồi reloadData
}
```

**Trạng thái thường:**
- Tiêu đề "Tài liệu". `viewWillAppear` gọi `reload()` để thấy ngay file vừa lưu khi quay về từ editor.
- Cell dùng `UIListContentConfiguration.subtitleCell()`:
  - text: tên file đầy đủ (kèm phần mở rộng)
  - secondary: `"PDF • 12 KB • 29/10/2026 10:30"`. Dùng `ByteCountFormatter` và `DateFormatter` (`.short`/`.short`), tạo **một lần** rồi lưu làm property.
  - image: SF Symbol theo loại: `doc.richtext` (pdf), `photo` (image), `doc.plaintext` (text)
- **Tap một dòng** hiện action sheet: "Sửa" → `onEdit`, "Xem trước in" → `onPrint([doc])`, "Huỷ". Trên iPad phải đặt `popoverPresentationController.sourceView/sourceRect` vào cell.
- **Long-press** hiện context menu (`contextMenuConfigurationForRowAt`) với 2 action giống trên, cộng thêm "Xoá" (destructive).
- **Swipe trái** để xoá (`trailingSwipeActionsConfigurationForRowAt`). Gọi `library.delete` rồi `reload()`. Nếu lỗi thì hiện alert.
- Khi danh sách trống, `tableView.backgroundView` là một label căn giữa: "Chưa có tài liệu. Bấm + để thêm."
- Nút trên nav bar:
  - trái: "+" mở `UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image, .plainText], asCopy: true)` với `allowsMultipleSelection = true`. Khi chọn xong, gọi `library.importFile` cho từng file rồi `reload()`. Nếu có file lỗi thì gom lại hiện một alert.
  - phải: "Chọn" để vào chế độ chọn nhiều.

**Chế độ chọn nhiều:**
- `tableView.allowsMultipleSelectionDuringEditing = true`, `setEditing(true)`.
- Nút phải đổi thành "Xong" (thoát chế độ chọn, bỏ chọn hết). Nút trái đổi thành "Chọn tất cả" / "Bỏ chọn".
- Toolbar dưới (`navigationController?.setToolbarHidden(false)`) có nút **"Xem trước in (n)"**, disable khi n = 0. Bấm vào thì gọi `onPrint(selectedInOrder)` rồi thoát chế độ chọn.
- **Thứ tự quan trọng:** lưu `private var selectionOrder: [URL]`, thêm vào ở `didSelectRowAt` và xoá ở `didDeselectRowAt`. Không dùng `indexPathsForSelectedRows` vì nó không giữ thứ tự chọn. Thứ tự file trong PDF = thứ tự người dùng chọn.
- Đang ở chế độ chọn thì tap dòng chỉ để chọn/bỏ chọn, không mở action sheet.
- Toolbar phải ẩn khi thoát chế độ chọn và khi push sang màn khác (`viewWillDisappear`).

### 2. Container + Coordinator
- `PrintFlowContainer.makeFileList(onEdit:onPrint:) -> FileListViewController`
- `PrintFlowCoordinator.start()`: đặt file list làm root của `navigationController`.
  - `onEdit` → `open(_:)` (task 04 sẽ đổi phần editor)
  - `onPrint` → `showPrintPreview(for: [SourceDocument])`. Ở task này chỉ cần tạo stub push Preview của file đầu tiên, hoặc gọi API của task 03 nếu đã xong.

### 3. Demo
- Xoá `PrintFlowDemo/HomeViewController.swift`.
- `RootView` trong `PrintFlowDemoApp.swift`: `SampleDocuments.seedIfEmpty(container.library)` rồi `coordinator.start()`. Coordinator phải được giữ sống, ví dụ trong `Coordinator` của `UIViewControllerRepresentable` (`makeCoordinator`), không dựa vào closure capture.

## Không làm
- Tìm kiếm, sắp xếp, thumbnail thật, đổi tên, chia sẻ.

## Tiêu chí hoàn thành
- [ ] Mở app thấy 4 file mẫu với icon và subtitle đúng
- [ ] Tap → action sheet → "Sửa" mở đúng editor theo loại file
- [ ] Chọn 3 file theo thứ tự C, A, B → `onPrint` nhận đúng [C, A, B]. Có thể kiểm tra bằng `print` tạm hoặc qua task 03.
- [ ] Nút "Xem trước in (n)" cập nhật n và disable khi n = 0
- [ ] Swipe xoá được, danh sách trống thì hiện empty state
- [ ] Import từ Files (simulator: kéo file vào Files app trước) xong thì file xuất hiện trong list
- [ ] Không có cảnh báo Auto Layout hay popover crash trên iPad simulator
