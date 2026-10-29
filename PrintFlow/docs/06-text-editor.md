# Task 06 — UI editor TXT

> Cần task 04. Đọc [00-README.md](00-README.md) và [04-editor-save-contract.md](04-editor-save-contract.md) trước.

## Mục tiêu
Sửa nội dung file `.txt` rồi Lưu. Task nhỏ nhất trong bộ.

## Màn hình
- Một `UITextView` full màn hình (bám safe area), font `.monospacedSystemFont(ofSize: 15, weight: .regular)`, bật `adjustsFontForContentSizeCategory` thông qua `UIFontMetrics`.
- Nav bar có nút "Lưu" (theo task 04). Thêm nút "Xong" để ẩn bàn phím (`resignFirstResponder`), chỉ hiện khi bàn phím đang mở. Có thể đặt "Xong" ở `inputAccessoryView` toolbar.
- **Bàn phím không được che nội dung.** iOS 15+ dùng `view.keyboardLayoutGuide`: neo `textView.bottomAnchor` vào `view.keyboardLayoutGuide.topAnchor`.
- `textViewDidChange` gán `hasChanges = (textView.text != originalText)`. Nút Lưu bật/tắt theo giá trị này.
- Subtitle hoặc prompt nhỏ hiện số dòng và số ký tự (không bắt buộc).

## Đọc file
- Thử đọc UTF-8 trước. Nếu thất bại thì thử `String(contentsOf:usedEncoding:)` để hệ thống tự đoán. Nếu vẫn thất bại thì throw `unreadable`. Phần này xử lý trong `PrintFlowContainer.makeEditor`.
- Khi lưu luôn ghi UTF-8. Ghi chú trong code rằng file gốc có encoding khác sẽ bị chuyển sang UTF-8.

## Không làm
- Cỡ chữ và lề khi in: đây là việc của bước convert (`TextStyle` mặc định trong task 03). TXT không lưu được font, nên đặt ở editor là vô nghĩa.
- Tìm/thay thế, đánh số dòng, highlight.

## Self-test
- File UTF-16 (ghi bằng `.utf16`) mở được qua `makeEditor`, không throw.

## Tiêu chí hoàn thành
- [x] Mở `mau.txt`, gõ thêm một dòng, Lưu đè → mở lại thấy dòng mới
- [x] Gõ ở cuối file dài không bị bàn phím che
- [x] Gõ rồi xoá về y như cũ → nút Lưu bị disable lại
- [x] Tiếng Việt có dấu lưu và đọc lại đúng


## Kết quả kiểm tra — 29/10/2026

- Build Debug cho iOS Simulator thành công; self-test in `SELFTEST OK` trên iPhone (iOS 26.4).
- `TextFileEditorViewController`: `UITextView` monospaced 15pt qua `UIFontMetrics`, bám safe area, đáy neo `keyboardLayoutGuide`; nút "Xong" ở `inputAccessoryView` (chỉ hiện khi bàn phím mở). `hasChanges` so với text lúc mở.
- `makeEditor` đọc UTF-8 trước, không được thì `String(contentsOf:usedEncoding:)`, vẫn lỗi thì throw `unreadable`. Lưu luôn UTF-8 (có ghi chú trong code).
- Self-test: mở file UTF-16 không throw; gõ thêm dòng có dấu → Lưu bật → lưu đè đọc lại bằng UTF-8 đúng nội dung; xoá về như cũ → Lưu tắt.
- Kiểm tra UI bằng kịch bản tạm (đã gỡ khỏi source): file 80 dòng, gõ ở cuối, dòng cuối nằm trên bàn phím và nút "Xong". Ảnh: `/tmp/printflow-task06-keyboard.png`. Chưa gõ tay vì máy chưa có AXe.
- Không làm hiển thị số dòng/ký tự (không bắt buộc).
