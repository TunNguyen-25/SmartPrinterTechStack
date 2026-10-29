# PrintFlow File List Implementation Plan

**Goal:** Thực hiện `PrintFlow/docs/02-file-list-screen.md`.
**Architecture:** UITableViewController nhận FileLibrary và closure; container dựng màn, coordinator điều hướng. RootView.Coordinator giữ vòng đời flow.
**Tech Stack:** UIKit, Swift 6, iOS 15; không thêm dependency hay sửa pbxproj.
**Spec:** `PrintFlow/docs/00-README.md`, `PrintFlow/docs/02-file-list-screen.md`.

## Các bước

- [x] Thêm self-test qua API UITableViewDelegate và bar button: thứ tự C/A/B, bỏ chọn/chọn lại, chọn tất cả, reload sau xoá, empty state và coordinator root.
- [x] Tạo FileListViewController: subtitle/icon, action sheet có anchor iPad, context menu, swipe xoá, import nhiều file và gom lỗi, toolbar chọn nhiều.
- [x] Thêm factory và start/showPrintPreview; task 03 chưa triển khai nên Preview dùng file đầu tiên. Thay HomeViewController và giữ coordinator bằng representable coordinator.
- [x] Build simulator, chạy SELFTEST OK, thao tác UI iPhone/iPad và chụp ảnh; cập nhật checklist đúng bằng chứng.

## Review focus

- Chọn lại file phải đưa file đó xuống cuối thứ tự; chọn tất cả giữ thứ tự đã chọn.
- Reload loại URL đã xoá, giữ selection theo URL khi thứ tự thư viện đổi.
- Toolbar ẩn khi push và trở lại đúng trạng thái khi quay về.
- Import một phần thành công vẫn reload và báo đủ lỗi còn lại.
- Action sheet iPad neo đúng cell; không tạo retain cycle qua callback.
