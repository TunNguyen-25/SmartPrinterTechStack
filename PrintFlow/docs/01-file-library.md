# Task 01 — FileLibrary (kho file)

> Đọc [00-README.md](00-README.md) trước. Task này không có UI.

## Mục tiêu
Tạo một service duy nhất quản lý các file mà app hiển thị và chỉnh sửa: liệt kê, import, lưu (đè hoặc tạo mới), xoá. Màn danh sách (02), editor (04) và file mẫu đều dùng chung service này.

## Việc cần làm

### 1. `PrintFlowKit/Library/FileLibrary.swift` (mới)

```swift
public enum SaveMode: Sendable { case overwrite, newCopy }

@MainActor
public final class FileLibrary {
    public struct Item: Sendable {
        public let document: SourceDocument
        public let modifiedAt: Date
        public let byteCount: Int
    }

    public let folder: URL                      // inject được để self-test dùng thư mục tạm
    public init(folder: URL)                    // tạo thư mục nếu chưa có
    public static func documents() -> FileLibrary   // <Documents>/PrintFlow

    public func items() -> [Item]               // chỉ file có FileKind hợp lệ, mới sửa nhất lên đầu, bỏ file ẩn
    public func importFile(at url: URL) throws -> SourceDocument   // copy vào folder, không ghi đè (tên trùng → "a (1).pdf")
    public func save(_ data: Data, for original: SourceDocument, mode: SaveMode) throws -> SourceDocument
    public func delete(_ document: SourceDocument) throws
}
```

Quy tắc của `save`:
- `.overwrite`: `data.write(to: original.url, options: .atomic)`, trả về document có cùng URL.
- `.newCopy`: ghi vào `uniqueURL(for: original.url.lastPathComponent)`, trả về document mới. Ví dụ: `mau.png` thành `mau (1).png`, nếu đã có thì `mau (2).png`.
- Phần mở rộng (extension) luôn giữ nguyên như file gốc. FileLibrary không chuyển định dạng.

`importFile`: nếu URL là security-scoped (lấy từ document picker) thì gọi `startAccessingSecurityScopedResource()` và `stop…` bao quanh lệnh copy. Nếu file không có `FileKind` hợp lệ thì throw `PrintFlowError.unsupported(url)`. Thêm case này vào `PrintFlowError`.

`uniqueURL`: copy logic từ `LANShare/LANShareKit/LANShareServer.swift` (`uniqueURL(for:in:)`, khoảng dòng 143) thành một hàm `private`. Không import LANShareKit.

`items()`: dùng `FileManager.contentsOfDirectory(at:includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles)`.

### 2. File mẫu
Sửa `PrintFlowDemo/SampleDocuments.swift` thành `static func seedIfEmpty(_ library: FileLibrary)`. Hàm này chỉ ghi 3 file mẫu (`mau.pdf`, `mau.png`, `mau.txt`) khi `library.items().isEmpty`. Thêm một ảnh JPG có nội dung dễ nhận ra khi xoay, ví dụ chữ "TOP" ở phía trên (dùng để kiểm tra task 05), lưu thành `anh.jpg`.

### 3. Container
`PrintFlowContainer` thêm `public let library: FileLibrary`, inject qua `init` với mặc định `FileLibrary.documents()`.

## Không làm
- iCloud, thư mục con, đổi tên, sắp xếp tuỳ chọn, tìm kiếm.
- Theo dõi thay đổi thư mục (FSEvents). Màn danh sách tự reload khi xuất hiện là đủ.

## Self-test (thêm vào `SelfTest.swift`)
Dùng `FileLibrary(folder: temporaryDirectory/selftest-<UUID>)`:
- import 1 file TXT → `items().count == 1`
- `save(.newCopy)` → có 2 file, file mới tên `… (1).txt`, file gốc không đổi nội dung
- `save(.overwrite)` → vẫn 2 file, nội dung file gốc đã đổi
- import trùng tên → không ghi đè
- import file `.zip` → throw
- `delete` → giảm số file

## Tiêu chí hoàn thành
- [ ] `FileLibrary` đúng API ở trên, đều là `public`
- [ ] Container có `library`, demo seed file mẫu vào `<Documents>/PrintFlow` ở lần chạy đầu
- [ ] Self-test mới pass, các self-test cũ vẫn pass
