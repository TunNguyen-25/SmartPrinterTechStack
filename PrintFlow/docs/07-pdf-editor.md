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
- [ ] Xoay trang 2, xoá trang 1, Lưu mới → file mới đúng số trang và đúng góc xoay
- [ ] Sắp xếp kéo-thả hoạt động, Huỷ không làm thay đổi gì
- [ ] Ghi chú bằng Markup rồi quay lại → thấy nét vẽ trong `PDFView`, lưu xong mở lại vẫn còn
- [ ] Nút Xoá bị disable khi chỉ còn 1 trang
