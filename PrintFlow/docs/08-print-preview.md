# Task 08 — UI Print Preview (màn chung trước khi in)

> Cần task 03. Đọc [00-README.md](00-README.md) và [03-print-pipeline.md](03-print-pipeline.md) trước.

## Mục tiêu
Đây là màn cuối cùng, dùng chung cho mọi loại file. Màn này xem trước PDF sẽ in, cho **sửa nhẹ cho lần in này** (xoay, xoá, sắp xếp trang) và **chỉnh thiết lập in**, sau đó bấm In. Các chỉnh sửa ở đây **không ghi vào file** trong thư viện.

## Màn hình

```
┌ < Tài liệu      3 tài liệu • 7 trang      In ┐
│                                              │
│         PDFView (tờ hiện tại)                │
│                                              │
├──────────────────────────────────────────────┤
│ [▢][▢][▣][▢] …   ← PDFThumbnailView          │
├──────────────────────────────────────────────┤
│ Khổ: A4 ▾   Hướng: Dọc ▾   ◐ Đen trắng [ ]   │  ← thanh thiết lập
├──────────────────────────────────────────────┤
│  ↻ Xoay   🗑 Xoá   ⇅ Sắp xếp                  │  ← toolbar trang
└──────────────────────────────────────────────┘
```

- Tiêu đề là `jobName`, prompt hoặc subtitle hiện số trang. Số trang phải cập nhật sau mỗi lần xoá.
- Nút "In" ở góc phải gọi `printService.print(pdf, settings:, jobName:, from: barButtonItem)` (đã có).

## Thiết lập in (`PrintSettings`)
- **Khổ giấy**: nút `UIButton` có `menu` (A4, Letter), `showsMenuAsPrimaryAction = true` (iOS 14+).
- **Hướng**: Dọc / Ngang, cũng dùng menu như trên.
- **Đen trắng**: `UISwitch` gán vào `settings.grayscale`. `PrintService` đã gửi giá trị này qua `UIPrintInfo.outputType`. Để preview cũng hiển thị xám, phủ lên `pdfView` một `UIView` (`isUserInteractionEnabled = false`, `backgroundColor = .white`, `layer.compositingFilter = "saturationBlendMode"`) và chỉ hiện khi bật. Nếu overlay hiển thị sai trên máy thật thì bỏ overlay, chỉ giữ cờ, và ghi `// TODO: preview grayscale`.

**Quan trọng, đổi khổ hoặc hướng giấy:** trang **ảnh** và **TXT** được convert theo `pageSize`, nên khi đổi khổ hoặc hướng phải **convert lại**. Cách làm:
- Preview phải giữ `documents: [SourceDocument]` và `converter` (inject thêm). `PrintFlowContainer.makePreview(for:)` truyền thêm 2 thứ này vào.
- Khi settings đổi → `pdf = try converter.pdf(from: documents, settings: settings)` → **reset luôn các chỉnh sửa trang**. Trước khi làm, nếu `hasPageEdits == true` thì hiện confirm "Đổi khổ giấy sẽ huỷ các thay đổi trang. Tiếp tục?".
- PDF gốc giữ nguyên khổ (xem task 03), AirPrint tự scale.

## Thao tác trang
Giống task 07: dùng `PDFPageEditor`. Màn sắp xếp **dùng lại** `PageReorderViewController` của task 07 nếu đã có. Nếu chưa có thì làm ở đây rồi task 07 dùng lại (khai báo `internal` trong Kit để cả hai cùng dùng).

## Không làm
- N-up (2/4 trang trên 1 tờ), chọn khoảng trang, số bản (đã có trong hộp thoại AirPrint), lưu PDF ra thư viện, chia sẻ, in trực tiếp qua IPP.
- Ghi TODO cho N-up trong `PDFPageEditor` (đã có).

## Self-test
- Đổi `isLandscape` rồi convert lại 1 ảnh → trang có width > height
- (Thao tác trang đã có test ở `PDFPageEditor`.)

## Tiêu chí hoàn thành
- [ ] Chọn 3 file từ list → Preview hiện đủ trang, thumbnail đúng thứ tự
- [ ] Xoá hoặc xoay trang → số trang và thumbnail cập nhật ngay
- [ ] Đổi A4 → Letter, Dọc → Ngang → trang ảnh/TXT đổi khổ. Có confirm khi đã sửa trang.
- [ ] Bấm In → hộp thoại AirPrint hiện ra. Trên simulator dùng **Printer Simulator** (Xcode › Open Developer Tool) để in thử và xem PDF output.
- [ ] Trên iPad, hộp thoại In hiện dạng popover gắn vào nút In, không crash
- [ ] Quay về list → file trong thư viện **không** bị thay đổi
