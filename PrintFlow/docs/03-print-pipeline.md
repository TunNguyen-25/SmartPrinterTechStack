# Task 03 — Pipeline in: n file → 1 PDF → Preview

> Cần task 01. Đọc [00-README.md](00-README.md) trước. Task này không có UI, ngoài một spinner.

## Mục tiêu
Từ danh sách file đã chọn (1 hoặc nhiều, khác loại cũng được), tạo **một** `PDFDocument` theo đúng thứ tự, rồi mở Print Preview.

## Việc cần làm

### 1. `PDFConverter` (sửa `Conversion/PDFConverter.swift`)

```swift
/// Ghép nhiều file thành 1 PDF theo thứ tự truyền vào.
public func pdf(from documents: [SourceDocument], settings: PrintSettings) throws -> PDFDocument
```

Quy tắc xử lý theo từng loại:
- **pdf**: mở bằng `PDFDocument(url:)`. Nếu file khoá, không mở được hoặc có 0 trang thì throw `PrintFlowError.unreadable(url)`. Copy từng trang (`page.copy() as? PDFPage`) rồi `insert` vào kết quả. **Giữ tham chiếu** các `PDFDocument` nguồn trong một mảng cục bộ đến cuối hàm, vì PDFKit có thể crash hoặc mất nội dung nếu tài liệu nguồn bị giải phóng trước khi kết quả được serialize. Xem ghi chú tương tự ở `SmartPrinterTechStack/SmartPrinterTechStack/Files/PDFEditing.swift`.
  - Trang PDF giữ **nguyên khổ gốc**, không ép về `settings.pageSize`. AirPrint sẽ tự scale.
- **image**: mỗi ảnh là một trang khổ `settings.pageSize`, aspect-fit, có lề 18pt. Đọc ảnh bằng **ImageIO downsample** (`CGImageSourceCreateThumbnailAtIndex`, `kCGImageSourceThumbnailMaxPixelSize = 3000`, `kCGImageSourceCreateThumbnailWithTransform = true`) để không load ảnh 48MP vào RAM. Ghi chú: `// ponytail: 3000px ≈ 300dpi cho A4, tăng nếu in khổ lớn`.
- **text**: đọc UTF-8 rồi gọi `pdf(from: text, style: TextStyle(), pageSize: settings.pageSize)` (hàm đã có).
- Danh sách rỗng thì throw. Nhớ thêm case `PrintFlowError.empty`.

Hàm này chạy đồng bộ trên main actor, vì `UISimpleTextPrintFormatter` bắt buộc chạy trên main. Với demo (vài file) thì chấp nhận được.

### 2. Container
```swift
func makePreview(for documents: [SourceDocument]) throws -> UIViewController
```
- Gọi `converter.pdf(from:settings: defaultSettings)`.
- `jobName`: nếu có 1 file thì dùng `document.name`, nếu nhiều thì `"\(n) tài liệu"`.
- Xoá hàm cũ `makePreview(for pdf: PDFDocument, jobName:)` nếu không còn ai gọi (sau task 04, editor không gọi Preview nữa).

### 3. Coordinator
```swift
func showPrintPreview(for documents: [SourceDocument])
```
- Hiện spinner (`UIActivityIndicatorView` trong một alert, hoặc overlay đơn giản trên `navigationController.view`), rồi `DispatchQueue.main.async` (nhường một vòng runloop để spinner kịp vẽ), sau đó convert, ẩn spinner và push Preview.
- Nếu lỗi thì hiện alert "Không chuyển được sang PDF" kèm tên file lỗi.

## Không làm
- Convert nền hoặc song song, cache PDF đã convert, Office (docx…).

## Self-test
- 3 file [txt dài 200 dòng, png, pdf 2 trang] → số trang = (số trang txt) + 1 + 2
- Thứ tự: trang đầu chứa text của file txt (`page(at:0)?.string`), trang cuối là trang cuối của pdf nguồn
- Trang ảnh có `bounds(for: .mediaBox).size == settings.pageSize`. Với `isLandscape = true` thì width > height.
- Danh sách rỗng → throw. PDF hỏng (ghi `Data("abc".utf8)` ra `.pdf`) → throw `unreadable`

## Tiêu chí hoàn thành
- [ ] Từ list (task 02), chọn nhiều file khác loại → Preview hiện đủ trang, đúng thứ tự chọn
- [ ] Ảnh lớn (ví dụ 6000×4000) convert không tăng RAM quá mức. Kiểm tra bằng Xcode memory gauge, nên < 150MB.
- [ ] Self-test pass
