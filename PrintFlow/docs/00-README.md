# PrintFlow — kế hoạch triển khai

Bộ tài liệu này chia việc code PrintFlow thành các task độc lập. Mỗi file `0x-*.md` là **một task**, giao cho một thread chat. Hãy đọc file này trước, sau đó đọc file task.

## Mục tiêu sản phẩm (demo cho khách)

```
┌──────────────────────── Danh sách file ────────────────────────┐
│  tap 1 file ──► [Sửa] ──► Editor theo loại ──► Lưu ──► quay về │
│             └─► [Xem trước in] ──┐                             │
│  chọn nhiều ──► [Xem trước in (n)]┤                            │
└───────────────────────────────────┼────────────────────────────┘
                                    ▼
                  chuyển 1..n file → 1 PDF (theo thứ tự đã chọn)
                                    ▼
          Print Preview chung (xoay/xoá/sắp trang, khổ giấy, đen trắng)
                                    ▼
                                AirPrint
```

- **Editor** chỉ có một việc: sửa rồi **Lưu**. Khi bấm Lưu sẽ hiện 2 lựa chọn: **Lưu đè** (ghi đè file gốc) hoặc **Lưu thành file mới** (tạo bản sao, file gốc giữ nguyên). File được lưu **theo đúng định dạng gốc**: ảnh vẫn là ảnh, TXT vẫn là TXT, PDF vẫn là PDF. Editor **không** đi sang Preview.
- **Print Preview** chỉ được mở từ danh sách file. Các chỉnh sửa trong Preview chỉ áp dụng cho lần in đó và **không** ghi vào file.

## Hiện trạng code (đã có, build OK, self-test OK)

```
PrintFlow/
├─ PrintFlow.xcodeproj           2 target: PrintFlowKit (framework) + PrintFlowDemo (app)
├─ PrintFlowKit/                 dùng file-system synchronized group: thêm file vào thư mục là vào target, KHÔNG cần sửa pbxproj
│  ├─ Models/SourceDocument.swift     FileKind (pdf/image/text), SourceDocument, PrintFlowError
│  ├─ Models/PrintSettings.swift      paper (A4/Letter), isLandscape, grayscale, pageSize
│  ├─ Conversion/PDFConverter.swift   [UIImage] → PDF, String → PDF (TextStyle)
│  ├─ Editors/*ViewController.swift   3 editor khung, hiện dùng onFinish(PDFDocument) → SẼ ĐỔI (task 04)
│  ├─ Editors/ImageEditingService.swift  rotateRight, grayscale
│  ├─ Preview/PDFPageEditor.swift     rotate, delete, move trang
│  ├─ Preview/PrintPreviewViewController.swift  khung, có nút In
│  ├─ Printing/PrintService.swift     AirPrint
│  └─ Flow/PrintFlowContainer.swift + PrintFlowCoordinator.swift
└─ PrintFlowDemo/                PrintFlowDemoApp, HomeViewController (SẼ THAY bằng file list), SampleDocuments, SelfTest
```

## Thứ tự task

| # | File | Phụ thuộc | Nội dung |
|---|------|-----------|----------|
| 01 | [01-file-library.md](01-file-library.md) | — | Kho file: liệt kê, import, lưu đè/lưu mới, xoá |
| 02 | [02-file-list-screen.md](02-file-list-screen.md) | 01 | Màn danh sách, chọn nhiều, thay HomeViewController |
| 03 | [03-print-pipeline.md](03-print-pipeline.md) | 01 | Chuyển n file → 1 PDF, nối vào Preview |
| 04 | [04-editor-save-contract.md](04-editor-save-contract.md) | 01 | Hợp đồng Lưu chung cho 3 editor, nối với coordinator |
| 05 | [05-image-editor.md](05-image-editor.md) | 04 | UI editor ảnh |
| 06 | [06-text-editor.md](06-text-editor.md) | 04 | UI editor TXT |
| 07 | [07-pdf-editor.md](07-pdf-editor.md) | 04 | UI editor PDF |
| 08 | [08-print-preview.md](08-print-preview.md) | 03 | UI Print Preview |

Có thể làm song song: 02 / 03 / 04 sau khi xong 01, và 05 / 06 / 07 sau khi xong 04.

## Quy ước bắt buộc (mọi task)

- **UIKit**, Swift 6, iOS **15.0**. API mới hơn phải có `if #available` kèm fallback.
- Target `PrintFlowKit` **không** đặt default actor isolation, vì vậy class UI và service phải ghi rõ `@MainActor`. Target Demo thì mặc định MainActor.
- **DI**: chỉ `PrintFlowContainer` được khởi tạo màn hình và service. Màn hình nhận dependency qua `init` và báo kết quả qua closure, không tự push màn khác. Mọi điều hướng nằm trong `PrintFlowCoordinator`.
- **Không thêm thư viện ngoài** (SPM/CocoaPods). Chỉ dùng PDFKit, ImageIO, Core Image, QuickLook, UIKit.
- Chuỗi hiển thị viết bằng tiếng Việt. Comment ngắn, cũng bằng tiếng Việt, theo phong cách code hiện có.
- Mỗi task phải thêm assert vào `PrintFlowDemo/SelfTest.swift` cho phần logic mới (không dùng XCTest).
- Không đổi bundle id, không sửa pbxproj, trừ khi task ghi rõ.

## Build & kiểm tra

Xcode nằm ở Desktop, không phải `/Applications`, nên phải đặt `DEVELOPER_DIR`:

```bash
cd PrintFlow
export DEVELOPER_DIR=/Users/anhtuannguyen/Desktop/Xcode.app/Contents/Developer
xcodebuild -project PrintFlow.xcodeproj -scheme PrintFlowDemo \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/printflow-dd build | grep -E "error|BUILD"

DEV=$(xcrun simctl list devices available | grep -m1 iPhone | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot $DEV 2>/dev/null
xcrun simctl install $DEV /tmp/printflow-dd/Build/Products/Debug-iphonesimulator/PrintFlowDemo.app
xcrun simctl launch --console-pty $DEV tuandev.PrintFlowDemo -selftest   # phải in "SELFTEST OK"
```

Task có UI: sau khi self-test OK, mở app trên simulator, tự bấm qua flow của task rồi chụp màn hình (`xcrun simctl io $DEV screenshot out.png`) để xác nhận.

**Định nghĩa "xong" cho mỗi task:** build không có error, self-test OK, đạt toàn bộ checklist "Tiêu chí hoàn thành" trong file task.
