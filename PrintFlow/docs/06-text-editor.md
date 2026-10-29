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
- [ ] Mở `mau.txt`, gõ thêm một dòng, Lưu đè → mở lại thấy dòng mới
- [ ] Gõ ở cuối file dài không bị bàn phím che
- [ ] Gõ rồi xoá về y như cũ → nút Lưu bị disable lại
- [ ] Tiếng Việt có dấu lưu và đọc lại đúng
