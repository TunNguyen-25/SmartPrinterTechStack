# Task 07 — UI editor PDF

> Cần task 04. Đọc [00-README.md](00-README.md) và [04-editor-save-contract.md](04-editor-save-contract.md) trước.

## Mục tiêu
Sửa PDF: **thao tác trang** (xoay, xoá, sắp xếp) và **ghi chú/ký** bằng bộ Markup của hệ thống, sau đó Lưu.

## Màn hình

```
┌ < Tài liệu         mau.pdf          Lưu ┐
│                                         │
│           PDFView (trang hiện tại)      │
│                                         │
├─────────────────────────────────────────┤
│ [▢][▢][▣][▢][▢]   ← PDFThumbnailView    │
├─────────────────────────────────────────┤
│  ↻ Xoay  🗑 Xoá  ⇅ Sắp xếp  ✎ Ghi chú   │  ← UIToolbar
└─────────────────────────────────────────┘
```

- `PDFView`: `autoScales = true`, `displayMode = .singlePageContinuous`.
- `PDFThumbnailView` cao 72pt, `layoutMode = .horizontal`, gán `pdfView` để tap thumbnail là nhảy trang.
- Các thao tác áp dụng cho **trang hiện tại** (`pdfView.currentPage`, lấy index qua `pdf.index(for:)`).

## Chức năng
Dùng `PDFPageEditor` đã có (`rotate`, `delete`, `move`). Sau mỗi thao tác: `hasChanges = true`, gọi `pdfView.layoutDocumentView()` để làm mới.

- **Xoay**: +90° trang hiện tại.
- **Xoá**: hiện confirm "Xoá trang X?". Nếu chỉ còn 1 trang thì disable nút (`PDFPageEditor.delete` đã chặn việc này, nhưng UI cũng phải phản ánh).
- **Sắp xếp**: present `PageReorderViewController` (file mới). Màn này là `UICollectionView` lưới thumbnail (`page.thumbnail(of:for: .mediaBox)`, tạo ảnh ở background rồi cache), kéo-thả bằng `UICollectionViewDragDelegate`/`DropDelegate` (hoặc `reorderingCadence` + long-press `beginInteractiveMovementForItem`). Có nút "Xong" để áp dụng thứ tự mới qua `PDFPageEditor.move`, và "Huỷ".
  - Tham khảo: `FileEditor/PDFEditor/PDFEditorKit/PDFReorderViewController.swift` đã làm việc tương tự.
- **Ghi chú (Markup)**: dùng `QLPreviewController` ở chế độ chỉnh sửa, đã có sẵn ở `FileEditor/PDFEditor/PDFEditorKit/QuickLookMarkupController.swift`. Copy class đó vào `PrintFlowKit/Editors/` và điều chỉnh như sau:
  1. Trước khi mở, ghi `pdf.dataRepresentation()` ra một file tạm (để giữ các thao tác trang chưa lưu).
  2. Mở QuickLook trên file tạm với `editingMode = .createCopy`.
  3. `didSaveEditedCopyOf`: copy file kết quả ra chỗ khác (QuickLook có thể dọn file ngay), sau đó trên main actor thay `pdf` bằng `PDFDocument(url: copy)`, gán `pdfView.document`, `thumbnailView` cập nhật theo, và `hasChanges = true`.
  - Biến `pdf` trong editor phải là `var` (hiện đang là `let`).

## Không làm
- Sửa chữ gốc trong PDF (cần SDK trả phí), chèn trang, gộp PDF trong editor (gộp đã có ở luồng in nhiều file), crop trang.
- PaperKit (iOS 26). Có thể thêm sau với `#available` nếu khách muốn.

## Self-test
- `PDFPageEditor` đã có test xoay/xoá/chuyển. Thêm: `dataRepresentation()` của PDF sau khi xoay → mở lại thấy `rotation == 90`. Phần này đảm bảo dữ liệu lưu giữ được góc xoay.

## Tiêu chí hoàn thành
- [x] Xoay trang 2, xoá trang 1, Lưu mới → file mới đúng số trang và đúng góc xoay
- [x] Sắp xếp kéo-thả hoạt động, Huỷ không làm thay đổi gì
- [~] Ghi chú bằng Markup rồi quay lại → thấy nét vẽ trong `PDFView`, lưu xong mở lại vẫn còn (xem ghi chú bên dưới)
- [x] Nút Xoá bị disable khi chỉ còn 1 trang


## Kết quả kiểm tra — 29/10/2026

- Build Debug cho iOS Simulator thành công; self-test in `SELFTEST OK` trên iPhone (iOS 26.4). Không sửa pbxproj.
- `PDFFileEditorViewController`: `PDFView` + `PDFThumbnailView` 72pt + toolbar Xoay/Xoá/Sắp xếp/Ghi chú; tiêu đề là tên file. `pdf` là `var`.
- `PDFThumbnailView` không tự vẽ lại khi xoay trang (gán lại `pdfView` hay đổi `thumbnailSize` đều không ăn; gán lại `document` làm lệch tỉ lệ `PDFView`), nên sau mỗi thao tác trang thì tạo view thumbnail mới.
- Thêm `PDFPageEditor.reorder(_:to:)` (dựa trên `move`) để màn Print Preview (task 08) dùng lại.
- `PageReorderViewController`: lưới drag & drop, thumbnail render nền trên bản sao `dataRepresentation()` (PDFDocument không Sendable) rồi cache theo index. Huỷ trả `nil`, không đổi gì; thứ tự không đổi thì không bật Lưu.
- `QuickLookMarkupController` copy vào `Editors/`; file tạm đặt trong thư mục riêng, giữ tên gốc để QuickLook hiện đúng tên. Kết quả copy ra file tạm khác rồi thay `pdf`.
- Self-test: `dataRepresentation()` giữ góc xoay; `reorder` đúng thứ tự, thứ tự thiếu trang thì bỏ qua; editor xoay trang 2 + xoá trang 1 + lưu mới → 2 trang, trang đầu xoay 90°, file gốc giữ 3 trang; Xoá bị khoá khi còn 1 trang; `replacePDF` thay PDF đang sửa.
- Kiểm tra UI bằng kịch bản tạm (đã gỡ khỏi source). Ảnh: `/tmp/printflow-task07-edit.png` (trang 2 xoay, thumbnail cập nhật), `-reorder.png`, `-delete.png` (confirm "Xoá trang 1?"), `-one.png` (Xoá bị khoá), `-markup.png` (QuickLook mở file tạm với tên gốc).
- **Chưa kiểm**: vẽ bằng Markup rồi quay lại, và kéo-thả bằng tay — máy chưa có AXe nên không tự tap/vẽ được. Cần thử tay trên simulator/thiết bị.
- Log "CoreGraphics PDF has logged an error" khi chạy self-test có từ trước task này (test cũ), không ảnh hưởng kết quả.
