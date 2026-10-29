# Task 05 — UI editor ảnh

> Cần task 04. Đọc [00-README.md](00-README.md) và [04-editor-save-contract.md](04-editor-save-contract.md) trước.

## Mục tiêu
Sửa ảnh ở mức cơ bản nhưng đủ để demo: **xoay, lật, crop, đen trắng, sáng/tương phản**, sau đó Lưu.

## Màn hình

```
┌ < Tài liệu        anh.jpg            Lưu ┐
│                                          │
│            [ ảnh, aspect-fit ]           │
│                                          │
├──────────────────────────────────────────┤
│  (thanh slider, chỉ hiện khi chọn Chỉnh) │
├──────────────────────────────────────────┤
│  ↻ Xoay   ⇋ Lật   ⌗ Cắt   ◐ Đen trắng   ☼ Chỉnh  ↺ Gốc │  ← UIToolbar
└──────────────────────────────────────────┘
```

- `UIImageView` dùng `contentMode = .scaleAspectFit`, nền `.secondarySystemBackground`.
- Toolbar dưới dùng `UIBarButtonItem(image: UIImage(systemName:), primaryAction:)`. Mỗi nút có `accessibilityLabel` tiếng Việt.
- Icon: `rotate.right`, `arrow.left.and.right.righttriangle.left.righttriangle.right`, `crop`, `circle.lefthalf.filled`, `slider.horizontal.3`, `arrow.uturn.backward`.

## Chức năng

Thêm các hàm sau vào `ImageEditingService` (đã có `rotateRight`, `grayscale`):

```swift
public func flipHorizontal(_ image: UIImage) -> UIImage
public func crop(_ image: UIImage, to normalizedRect: CGRect) -> UIImage   // rect trong 0…1, toạ độ ảnh đã chuẩn hoá orientation
public func adjust(_ image: UIImage, brightness: Float, contrast: Float) -> UIImage   // CIColorControls; brightness -0.5…0.5, contrast 0.5…1.5
```

- **Xoay / Lật / Đen trắng**: áp dụng ngay lên `image`, `hasChanges = true`.
- **Chỉnh**: hiện 2 `UISlider` (Sáng, Tương phản). Khi kéo slider, render preview trên **ảnh đã downsample** (≤ 1200px) để mượt, giữ ảnh gốc riêng. Khi đóng panel, áp dụng lên ảnh full-size **một lần**.
- **Cắt**: push hoặc present `ImageCropViewController` (file mới cùng thư mục). Màn này hiện ảnh kèm khung crop có 4 góc kéo được, nền ngoài khung tối đi, có nút "Xong" và "Huỷ". Kết quả trả về `normalizedRect`.
  - Có thể tham khảo overlay kéo góc ở `FileEditor/PDFEditor/PDFEditorKit/PDFCropViewController.swift` (class overlay vẽ bằng `draw(_:)` + pan gesture).
  - Không thêm thư viện crop. Nếu sau này cần tỉ lệ khung cố định thì mới cân nhắc TOCropViewController hoặc Mantis.
- **Gốc** (↺): quay về ảnh lúc mở, `hasChanges = false`.
- Lưu: dùng hợp đồng task 04 (`ImageEditingService.encode(image, as: originalType)`).

**Lưu ý orientation:** ảnh từ camera có `imageOrientation != .up`. Ngay khi load, chuẩn hoá về `.up` bằng cách vẽ lại qua `UIGraphicsImageRenderer`, nếu không thì crop/xoay sẽ bị lệch.

## Không làm
- Vẽ, chèn chữ, sticker, crop phối cảnh (đã có trong DocumentScanner, tách riêng nếu cần).

## Self-test
- `flipHorizontal` hai lần → pixel góc (0,0) như ban đầu. Dùng ảnh 2×1 có 2 màu khác nhau.
- `crop(to: CGRect(x: 0, y: 0, width: 0.5, height: 1))` trên ảnh 40×20 → 20×20
- `adjust(brightness: 0, contrast: 1)` giữ nguyên kích thước

## Tiêu chí hoàn thành
- [ ] Mở `anh.jpg` → xoay → lưu mới → file mới đã xoay và vẫn là JPEG
- [ ] Crop hoạt động với ảnh ngang lẫn ảnh dọc, khung crop không vượt ra ngoài ảnh
- [ ] Kéo slider mượt (không giật trên simulator)
- [ ] Nút Lưu bị disable cho đến khi có thay đổi
- [ ] Self-test pass
