# Task 04 — Hợp đồng "Lưu" chung cho 3 editor

> Cần task 01. Đọc [00-README.md](00-README.md) trước. Task này chỉ làm **khung lưu**. UI chỉnh sửa của từng editor nằm ở task 05/06/07.

## Mục tiêu
Cả 3 editor có chung một hành vi: nút **Lưu** → chọn **Lưu đè** hoặc **Lưu thành file mới** → ghi file theo định dạng gốc → quay về danh sách và thấy file đã cập nhật.

## Thay đổi hợp đồng

Hiện tại các editor nhận `onFinish: (PDFDocument) -> Void` và tự convert sang PDF. **Bỏ cách này.** Thay bằng:

```swift
/// Editor đưa ra dữ liệu đã encode theo định dạng gốc; editor không tự ghi file.
public typealias EditorSaveHandler = (_ data: Data, _ mode: SaveMode) throws -> Void
```

Mọi editor có `init(..., onSave: @escaping EditorSaveHandler)` và **không còn** phụ thuộc vào `PDFConverter` hay `PrintSettings`.

| Editor | Dữ liệu ra |
|---|---|
| Image | encode bằng **ImageIO** (`CGImageDestinationCreateWithData`) với `UTType(filenameExtension: original ext)`: jpg → `.jpeg` (chất lượng 0.9), png → `.png`, heic → `.heic`. Nếu destination trả nil (ví dụ HEIC trên một số simulator) thì throw `PrintFlowError.cannotEncode`. |
| Text | `Data(text.utf8)` |
| PDF | `pdf.dataRepresentation()`. Nếu nil thì throw `cannotEncode` |

Thêm `case cannotEncode` vào `PrintFlowError`. Có thể thêm `LocalizedError` với thông báo tiếng Việt cho mọi case.

Editor cần biết phần mở rộng gốc (để encode ảnh), nên truyền `SourceDocument` vào `init` của editor ảnh, hoặc truyền `UTType`.

## Việc cần làm

### 1. `PrintFlowKit/Editors/SaveOptions.swift` (mới)
Một helper dùng chung để các editor không phải viết lại action sheet:

```swift
@MainActor
enum SaveOptions {
    /// Action sheet: "Lưu đè" (destructive) / "Lưu thành file mới" / "Huỷ".
    static func present(from viewController: UIViewController, barButtonItem: UIBarButtonItem?, onPick: @escaping (SaveMode) -> Void)
}
```
- Message của sheet: `"Lưu đè sẽ thay thế file gốc."`
- iPad: `popoverPresentationController?.barButtonItem = barButtonItem`

### 2. Mỗi editor (khung, chưa cần UI chỉnh sửa)
- Nút phải trên nav bar là "Lưu" (thay cho "Tiếp"). Bấm vào gọi `SaveOptions.present`, chọn xong thì `do { try onSave(makeData(), mode) } catch { alert lỗi }`.
- `private func makeData() throws -> Data` encode theo bảng ở trên.
- Mỗi editor có `private var hasChanges = false`. Khi `hasChanges == false` thì nút Lưu bị disable. Ở task này chỉ cần biến và logic enable/disable; task 05–07 sẽ set `true` khi người dùng sửa.

### 3. Container
```swift
func makeEditor(for document: SourceDocument, onSaved: @escaping (SourceDocument) -> Void) throws -> UIViewController
```
- Bên trong, tạo `onSave` như sau: `{ data, mode in onSaved(try self.library.save(data, for: document, mode: mode)) }`.
- Bỏ các tham số `converter` và `defaultSettings` khỏi editor ảnh và editor TXT.

### 4. Coordinator
- `open(_:)` → `makeEditor(for:onSaved:)`. Trong `onSaved`, gọi `navigationController?.popViewController(animated: true)`. File list tự reload ở `viewWillAppear` (task 02).
- Xoá `showPreview(_ pdf:…)` cũ, vì editor không đi tới Preview nữa.

### 5. Self-test cũ
Phần self-test đang gọi trực tiếp `PDFConverter` vẫn giữ. Cập nhật những gì bị vỡ do đổi init.

## Không làm
- Hỏi "Bỏ thay đổi?" khi bấm Back lúc chưa lưu. Ghi lại thành TODO.
- Undo/redo.

## Self-test
- Encode ảnh: tạo `UIImage` 40×20 → encode với `.png` và `.jpeg` → `CGImageSourceCreateWithData` đọc lại được, kích thước 40×20, `CGImageSourceGetType` đúng UTType.
  - Để test được thì đưa hàm encode ảnh ra thành `static func encode(_ image: UIImage, as type: UTType) throws -> Data` trong `ImageEditingService`.
- Luồng lưu: `FileLibrary` tạm + `makeEditor` với file TXT → gọi trực tiếp closure `onSave` (không qua UI) với `.newCopy` → library có 2 file.

## Tiêu chí hoàn thành
- [ ] 3 editor đều có nút Lưu và action sheet 2 lựa chọn. Nút Lưu bị disable khi chưa sửa.
- [ ] Lưu đè: file gốc đổi, số file không đổi. Lưu mới: xuất hiện `tên (1).ext`, file gốc giữ nguyên.
- [ ] Sau khi lưu thì tự quay về danh sách và thấy ngay thay đổi (ngày sửa, file mới)
- [ ] Editor không còn import hay dùng `PDFConverter`
- [ ] Self-test pass
