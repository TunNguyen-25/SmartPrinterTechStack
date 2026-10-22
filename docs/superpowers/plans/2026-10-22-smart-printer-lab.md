# Smart Printer Tech Stack Lab — Implementation Plan

> **For agentic workers:** Dùng `superpowers:executing-plans`. Theo yêu cầu người dùng ngày 22/10/2026: chỉ thực hiện một task mỗi lượt, cập nhật plan rồi dừng để review; không tự chuyển sang task kế tiếp.

**Goal:** Tạo app thử nghiệm các stack iOS theo ba tab Printer, Scan, File, ưu tiên native trước và so sánh một số thư viện sau.

**Architecture:** Giữ UIKit/iOS 15; tab controller và navigation riêng từng tab. Dùng thư viện file local chung, các công cụ native gọi trực tiếp framework Apple; chỉ thêm hai dependency cho bài so sánh có mục tiêu.

**Tech Stack:** UIKit, PDFKit, Quick Look, VisionKit, Vision, PhotosUI, Core Image/Core Graphics, Image I/O, UniformTypeIdentifiers, WebKit, ContactsUI, Network, Foundation; Mantis và ZLImageEditor ở giai đoạn sau.

**Spec:** [Thiết kế và phạm vi](../specs/2026-10-22-smart-printer-lab-design.md). [Research gốc](../../smart-printer-ios-research.md).

## Global Constraints

- App minimum **iOS 15.0**, iPhone/iPad; dùng Xcode 26.4 đang cài, không tự nâng target/toolchain.
- Chỉ **3 tab: Printer, Scan, File**. Hoàn chỉnh luồng native trước khi thêm thư viện.
- Input gốc không bị ghi đè; output chỉ xuất hiện khi lưu thành công; mọi nguồn dùng chung DocumentStore.
- Không backend/database/account/analytics; không SDK hãng hoặc PDF trả phí trong phạm vi hiện tại.
- Mỗi công cụ thể hiện stack, điều kiện OS/hardware và trạng thái thực; không giả lập thành công của in/scan.
- Giữ diff có sẵn trong project.pbxproj và research; không gom chúng vào thay đổi ngoài ý muốn.

## Review Focus

1. File từ cloud/extension có URL tạm hết hạn: phải copy xong trước khi báo thành công — Task 1, 6.
2. PDF mã hóa, cấm in/sửa hoặc file giả phần mở rộng: báo lỗi đúng, giữ nguyên input — Task 2, 3.
3. Camera không hỗ trợ hoặc bị từ chối quyền: có fallback Photos/Files, không crash — Task 4.
4. Ảnh 48 MP/PDF 50 trang, hủy hoặc thiếu dung lượng: không decode toàn bộ cùng lúc, không mất bản gốc — Task 1, 3, 4, 8.
5. PDF xoay/crop/annotation và khổ A4/Letter: lưu/mở lại/in không lệch hoặc mất nội dung — Task 3, 8.

## Phạm vi file dự kiến

Các đường dẫn sau tính từ repo root. Chỉ tạo file khi task cần đến, không dựng trước framework plugin hay layer repository.

- Sửa `SmartPrinterTechStack/SmartPrinterTechStack/SceneDelegate.swift`, `Info.plist` và `SmartPrinterTechStack/SmartPrinterTechStack.xcodeproj/project.pbxproj`: root, document types, permissions, targets/capabilities cần thiết.
- Thay placeholder `SmartPrinterTechStack/SmartPrinterTechStack/ViewController.swift` bằng `AppTabBarController.swift`.
- Tạo dưới `SmartPrinterTechStack/SmartPrinterTechStack/`: `Documents/{LibraryDocument,DocumentStore}.swift`, `Files/{FilesViewController,ImportViewController,DocumentPreviewViewController,PDFEditorViewController,ImageEditorViewController,ContentToPDFViewController}.swift`, `Printer/{PrinterViewController,PrintService,BonjourViewController}.swift`, `Scan/{ScanViewController,OCRService}.swift`.
- Giai đoạn nhận share: `SmartPrinterTechStack/SmartPrinterShareExtension/{ShareViewController.swift,Info.plist,SmartPrinterShareExtension.entitlements}`, app `SmartPrinterTechStack/SmartPrinterTechStack/SmartPrinterTechStack.entitlements`; mã xử lý inbox dùng chung trong `SmartPrinterTechStack/Shared/ShareInbox.swift`.
- Giai đoạn so sánh: `SmartPrinterTechStack/SmartPrinterTechStack/Files/EditorComparisonViewController.swift`, project package references và `Package.resolved` do Xcode tạo.
- Test: bổ sung test có ý nghĩa trong `SmartPrinterTechStack/SmartPrinterTechStackTests/` và `SmartPrinterTechStack/SmartPrinterTechStackUITests/`; bộ mẫu app ở `SmartPrinterTechStack/SmartPrinterTechStack/Resources/Samples/`, fixture lỗi/khóa ở test resources. Không dùng tài liệu cá nhân làm fixture.

## Thứ tự triển khai

### Task 1 — Ba tab, kho file và import Files/Photos

**Đợt 1: app đã mở được file thật.**

**Trạng thái 22/10/2026:** Đã triển khai và pass kiểm thử tự động; dừng để người dùng review. Các kiểm tra thủ công chưa chạy được liệt kê riêng bên dưới.

**Files:** AppTabBarController, SceneDelegate, Info.plist, project.pbxproj, LibraryDocument, DocumentStore, FilesViewController, ImportViewController, DocumentPreviewViewController; DocumentStoreTests và UI tests.

**Interfaces:** `LibraryDocument: Identifiable, Sendable` gồm `id: UUID`, `url: URL`, `name: String`. `actor DocumentStore` cung cấp `importFile(at: URL, preferredName: String?, id: UUID = UUID()) throws -> LibraryDocument`, `list() throws -> [LibraryDocument]`, `rename(id: UUID, to: String) throws -> LibraryDocument`, `delete(id: UUID) throws`. Caller dùng `await`; mỗi tài liệu có UUID directory riêng. Initializer nhận `rootURL: URL` để test trong thư mục tạm. `id` mặc định mới cho import thông thường; inbox truyền ID ổn định, nếu ID đã có bản hoàn chỉnh thì trả bản đó, không ghi đè hoặc sinh duplicate.

- [x] Viết test import hai file trùng tên không ghi đè nhau; rename không cho path traversal; source không tồn tại không tạo record; lỗi ghi/hủy copy không xuất hiện file hoàn chỉnh trong list. Chạy test và xác nhận fail trước phần triển khai.
- [x] Thiết lập root 3 tab; bỏ Main storyboard references đồng bộ trong build settings và scene manifest, giữ LaunchScreen. Không đổi AppDelegate nếu không cần.
- [x] Làm kho Documents với staging + move sau thành công, list/rename/delete, thumbnail cache; import nhiều file/ảnh theo từng item và báo lỗi riêng. Copy URL từ item provider trước khi callback trả về; không nạp cả batch ảnh full-size vào RAM.
- [x] Preview PDF/ảnh và Quick Look cho loại khác khi được hỗ trợ; thêm share/export Files, tìm theo tên và sample offline.
- [x] Xác nhận test pass; UI test thấy đúng 3 tab, nhập fixture, đổi tên, mở lại app vẫn thấy file; hủy Files/Photos picker, preview ảnh, share và hủy export. Kiểm tra share/export trên iPad simulator đã pass.
- [ ] Kiểm tra thủ công còn lại (**Not run**): cloud file chưa download/offline, nhiều ảnh Photos thật, duplicate name qua provider thật, hủy giữa lúc provider tải/copy, thiếu dung lượng. Đợt này chưa cần máy in.

### Task 2 — Tìm printer và in native

**Đợt 1 tiếp: file đã nhập in được qua hệ thống.**

**Files:** PrinterViewController, PrintService, DocumentPreviewViewController, project test fixtures; PrintServiceTests.

**Interfaces:** `@MainActor PrintService` cung cấp `choosePrinter(from: UIViewController)`, `presentPrint(document: LibraryDocument, from: UIViewController)`; lưu selected printer URL, contact lại trước khi hiển thị capability/in trực tiếp. UI gọi từ Printer và preview bằng cùng service.

- [ ] Test kiểm tra nội dung PDF/ảnh hợp lệ được chuẩn bị, file hỏng và PDF cấm in bị từ chối trước present; nhiều ảnh giữ đúng thứ tự khi tạo một PDF. Xác nhận fail rồi triển khai.
- [ ] Tích hợp picker, contact status, lưu/khôi phục URL, capability color/duplex; print sheet có preview, callback lỗi/hủy và anchor iPad.
- [ ] Thêm hành động in trực tiếp riêng sau review file và trang calibration A4/Letter; không báo “đã in ra giấy” từ completion.
- [ ] Test pass; manual printer online/offline, đổi printer, hủy, PDF nhiều trang, color/duplex theo máy. Ghi model/firmware/mạng và kết quả bản giấy; nếu không có phần cứng đánh dấu chưa kiểm chứng.

### Task 3 — Sửa PDF và ảnh native

**Đợt 2: import → edit → lưu → in hoàn chỉnh.**

**Files:** PDFEditorViewController, ImageEditorViewController, DocumentPreviewViewController, DocumentStore; PDFEditingTests, ImageEditingTests.

**Interfaces:** editor nhận `LibraryDocument` và `DocumentStore`; lưu bản sao bằng đường import của Task 1. Helper `makeEditedPDF(source: URL, pageIndices: [Int], rotations: [Int: Int]) throws -> URL` trả staging output; các thao tác merge/split/crop cùng làm trên bản làm việc, không sửa input đang preview.

- [ ] Test PDF reorder/rotate/delete/merge/split/crop bằng tài liệu nhỏ có text/annotation; output reopen đúng trang, text/annotation còn, input byte-for-byte không đổi. Reject index ngoài phạm vi và xóa hết trang. Xác nhận fail trước code.
- [ ] Làm thumbnail selection, thao tác trang và lưu bản sao PDFKit; reject/quy định unlock cho PDF khóa và tôn trọng permissions. Không raster hóa toàn bộ PDF, không cung cấp redaction hoặc sửa chữ gốc.
- [ ] Tích hợp Quick Look markup với delegate lưu cả bản copy; kiểm tra capability edit thực tế, hủy không tạo output. Kết quả callback tạm phải được nhập bền trước khi báo lưu.
- [ ] Test ảnh EXIF orientation, crop sát mép, rotate/flip/resize, grayscale và kích thước export; implement Core Image/Core Graphics và Image I/O downsample preview, áp dụng chỉnh sửa từ nguồn gốc.
- [ ] Test pass; manual lưu/mở lại/print markup, crop trên trang đã xoay, alpha PNG, HEIC, ảnh 48 MP, cancel/lỗi ghi; kiểm tra memory bằng Instruments trên thiết bị ở đợt cuối.

### Task 4 — Scan nhiều trang và OCR

**Đợt 3: scan → PDF → edit → in.**

**Files:** ScanViewController, OCRService, Info.plist, DocumentStore; ScanExportTests và OCR tests với ảnh có transcript.

**Interfaces:** `OCRService.recognize(imageAt: URL, languages: [String]) async throws -> String`; service kiểm tra languages theo request/revision. Scan export trả PDF URL để nhập qua DocumentStore, không giữ một mảng bitmap đã decode cho toàn bộ tài liệu.

- [ ] Test ghép 3 ảnh thành PDF đúng thứ tự/hướng/trang, hủy export không tạo tài liệu hoàn chỉnh. OCR fixture rõ chữ có expected text ngắn; kiểm tra ngôn ngữ không hỗ trợ có thông báo phù hợp.
- [ ] Thêm camera usage string, support/permission checks, cancel/error và fallback Photos/Files; tạo PDF theo từng trang với progress, lưu trước khi share/print.
- [ ] OCR accurate ngoài main actor; hiển thị/copy/export text, duration và languages thực sự dùng. Không mặc định `.async` tự chuyển công việc nặng khỏi main actor.
- [ ] iOS 16+ helper có `@available` và caller `#available`: searchable PDF export và DataScanner với `isSupported/isAvailable`; iOS 15 giữ scan + text riêng. iOS 26+ structured document extraction; fallback OCR thường trên OS cũ.
- [ ] Chạy tests; manual camera denied/restricted/unsupported, scan nhiều trang, OCR Việt/Anh, mờ/xoay, hủy, save rồi mở lại. Reopen searchable output và thử search/copy text trong app khác trước khi xác nhận nhãn searchable.

### Task 5 — Nguồn nhập bổ sung trong app

**Đợt 4: mở rộng nguồn, tái sử dụng kho file và editor.**

**Files:** ImportViewController, ContentToPDFViewController, SceneDelegate, Info.plist; ImportValidationTests, ContentToPDFTests và UI tests.

**Interfaces:** SceneDelegate xử lý URL từ `connectionOptions` lẫn `openURLContexts`; chuyển về DocumentStore. Các nguồn tạo/tải file trả local URL rồi đi qua cùng đường import, không tạo storage riêng.

- [ ] Test phần mở rộng giả, URL không HTTPS, HTTP 404, tải bị hủy và response vượt giới hạn không được báo thành công. Đặt giới hạn download **100 MiB**, timeout request **60 giây**, kiểm tra byte thực cả khi thiếu Content-Length và không theo redirect sang scheme khác HTTPS. Dùng URLProtocol stub cho transport trong unit test.
- [ ] Thêm URL download, nút Dán, drag/drop, document Open In cold/warm launch; validate định dạng bằng decoder/parser, không chỉ filename. File nguồn được giữ nguyên.
- [ ] Thêm web/text/contact-to-PDF. Web dùng print formatter/render theo trang A4; text tiếng Việt dài phải xuống trang, không cắt cuối; contact chỉ in trường đã chọn. Chỉ truy cập web khi người dùng mở link và không tự dùng account cloud.
- [ ] Test text Việt dài nhiều trang, HTML nhiều trang, contact thiếu field không crash; manual Files provider chưa tải/offline, SMB/USB nếu có, clipboard ảnh/text/URL và iPad drag/drop.
- [ ] Ghi nguồn nào đã test trên thiết bị, nguồn nào chỉ có đường hỗ trợ qua Files. Office chỉ preview nếu Quick Look hỗ trợ, có giải thích khi không edit/in được.

### Task 6 — Nhận file qua Share Extension

**Đợt 4 tiếp: Share từ các app khác.**

**Files:** Share Extension target, app/extension entitlements, Shared/ShareInbox.swift, SceneDelegate, project.pbxproj; ShareInboxTests.

**Interfaces:** `ShareInbox.enqueue(fileAt: URL) throws -> UUID`, `pending() throws -> [URL]`, `remove(_ url: URL) throws`; thư mục mỗi item chỉ được công bố sau ghi xong. Host drain khi foreground, import thành công mới remove; UUID inbox dùng làm stable import ID để retry sau crash không tạo bản trùng.

- [ ] Test item provider URL bị xóa sau callback nhưng bản inbox vẫn đọc được; failure giữa copy không xuất hiện item hoàn chỉnh; app restart sau import nhưng trước remove không tạo duplicate.
- [ ] Tạo target nhận PDF/ảnh/text/URL, cấu hình activation rule cụ thể, App Group inbox bền và signature/capability đúng app + extension; giới hạn mỗi attachment nhận share **100 MiB**, kiểm tra khi copy. Không tự mở main app bằng responder-chain/private URL trick.
- [ ] App nhận inbox khi khởi động/foreground, cho retry mục lỗi; không xóa attachment gốc hoặc inbox lỗi. Lỗi App Group/signing được báo blocker thực tế nếu team không cấp được capability.
- [ ] Test pass; chạy app thật để bật extension, share từ Safari, Files, Photos và Mail/Gmail/Messages khi có. Ghi rõ loại item từng app cung cấp; không hứa đọc mailbox hay mọi attachment.

### Task 7 — So sánh thư viện và custom discovery

**Đợt 5: đánh giá stack dựa trên baseline đã chạy.**

**Files:** EditorComparisonViewController, BonjourViewController, project.pbxproj, Package.resolved; comparison fixtures và UI smoke tests.

**Interfaces:** comparison nhận cùng `LibraryDocument`; mỗi lựa chọn mở editor riêng, callback trả output qua DocumentStore. Bonjour hiển thị service endpoint/TXT, không tự đẩy sang đường in khi chưa xác minh URL/capability.

- [ ] Build spike Mantis v3.1.0 và ZLImageEditor 3.0.0 lần lượt với toolchain hiện có; kiểm tra license, resources và deployment minimum. Pin tag và lockfile; không dùng latest tùy ý, không nâng app target để ép build.
- [ ] Tạo lựa chọn Native / Mantis cho crop, Native / ZLImageEditor cho editor. Smoke test mở, hoàn tất, cancel; fixture portrait/landscape/alpha/orientation cho cùng input, output khác tên, không ghi đè.
- [ ] Hiển thị kết quả export: stack/version, input, pixel, bytes, duration và lỗi; tách processing duration với thời gian thao tác UI. So sánh khả năng/UX/chất lượng trên output thật, không chỉ số dòng tích hợp.
- [ ] Thêm Bonjour `_ipp._tcp`/`_ipps._tcp`, Local Network usage string và Bonjour services chỉ tại task này; xử lý denied/waiting/no results, stop browser khi đóng màn hình. Không tắt TLS verification, không thêm IPP client hoặc SDK hãng.
- [ ] Xác nhận baseline vẫn pass sau dependency; manual Bonjour trên mạng/printer thật và quyền denied. Ghi package/discovery nào blocked hoặc chưa test, không hiển thị nút hoạt động giả.

### Task 8 — Kiểm tra trọn luồng và ghi kết quả

**Files:** tests, sample fixtures và `docs/smart-printer-lab-validation.md`.

- [ ] Chọn simulator thật từ `xcrun simctl list devices available` và scheme từ `xcodebuild -list -project SmartPrinterTechStack/SmartPrinterTechStack.xcodeproj`; không hardcode tên máy chưa tồn tại.
- [ ] Build Debug/Release cho iOS simulator/device SDK không signing nếu chỉ kiểm tra compile; chạy unit/UI tests trên runtime tương thích. Lệnh mẫu sau khi có UUID: `xcodebuild test -project SmartPrinterTechStack/SmartPrinterTechStack.xcodeproj -scheme SmartPrinterTechStack -destination 'platform=iOS Simulator,id=<UUID thực tế>'`. Unit tests hiện target 26.4; dùng runtime phù hợp và tách kiểm tra baseline iOS 15 trên thiết bị/runtime nếu có.
- [ ] UI tests: ba tab, sample import → edit → save/relaunch, scan fallback, chuyển file sang Printer, cancel không mất dữ liệu. Không viết test chỉ mirror getter hoặc snapshot UIKit system sheet.
- [ ] Trên thiết bị: PDF 50 trang, scan 20–50 trang, ảnh 48 MP, thiếu dung lượng, background/cancel; đo memory/time bằng Instruments. Không đặt ngưỡng hiệu năng tùy ý trước khi có baseline.
- [ ] In thật A4/Letter, portrait/landscape, color/mono, duplex nếu hỗ trợ, PDF xoay/crop/markup, ảnh sau edit; đo thước calibration. Kiểm tra offline/guest Wi-Fi và printer ngủ.
- [ ] Kiểm tra dark mode, Dynamic Type, VoiceOver labels, xoay iPad và popover anchors. Audit permission keys/availability/fallback đúng từng đường chạy.
- [ ] Ghi bảng Pass/Fail/Blocked/Not run với OS/device, model printer, input và artifact kết quả; kết luận native đủ ở đâu và library nào đáng giữ. Không gọi “đã hỗ trợ” cho case chưa chạy.

## Tiến độ và điểm dừng

- **Task 1: hoàn tất triển khai và kiểm thử tự động, chờ review** — ba tab, DocumentStore, Files/Photos, preview, share/export và bộ mẫu offline. Các kiểm tra thủ công chưa chạy vẫn để unchecked; chưa chứng nhận các trường hợp đó.
- **Task 2–8: chưa bắt đầu**. Dừng sau Task 1 để người dùng review.
- Mã nằm trong working tree của `research/tech_stack`, chưa commit; không có thay đổi có sẵn khi bắt đầu lượt này.

### Kiểm chứng Task 1

- RED: suite 9 unit test kho file thất bại với 28 issue trước implementation; UI test fail do chưa có tab File. Test ảnh đúng hướng fail trước khi có downsample.
- GREEN cuối: **13 unit test, 5 UI test và 4 lượt launch theo cấu hình giao diện** đều pass trong một lượt chạy toàn bộ suite trên **iPhone 17 Pro / iOS 26.4** (UUID `D6759AEC-CFFC-4FBF-BCA5-6E7EE4D82EC8`). Bao gồm kiểm tra dọn staging khi công bố file thất bại, giữ bản gốc và không ghi đè ID đã hoàn chỉnh.
- **iPad Pro 13-inch (M5) / iOS 26.4** (UUID `6DFA6BB0-FED1-42E1-AD6D-1C2D0C4182FD`): hai smoke test preview ảnh/export-cancel và Quick Look text/share-copy-delete đã pass. UI test thích ứng với tab ở phía trên và kiểu accessibility của sheet hệ thống; production code dùng UIKit chuẩn.
- Lệnh chạy toàn bộ suite: `xcodebuild test -project SmartPrinterTechStack/SmartPrinterTechStack.xcodeproj -scheme SmartPrinterTechStack -destination 'platform=iOS Simulator,id=D6759AEC-CFFC-4FBF-BCA5-6E7EE4D82EC8' -derivedDataPath /tmp/smart-printer-lab-derived -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`.
- Kết quả cuối: `TEST SUCCEEDED`, exit 0; artifact: `/tmp/smart-printer-lab-derived/Logs/Test/Test-SmartPrinterTechStack-2026.10.22_11-06-06-+0700.xcresult`. Log và ledger ở `.superpowers/sdd/2026-10-22-smart-printer-lab/` (local, git-ignored).
- `plutil -lint` cho Info.plist/project.pbxproj và `git diff --check` đã pass.
- App target vẫn iOS 15.0; unit-test target giữ iOS 26.4. AppDelegate, research, dependencies và entitlements không đổi.
- Chưa kiểm chứng trên thiết bị thật: file cloud chưa download/offline, nhập nhiều ảnh Photos thật, hủy trong lúc provider tải/copy, thiếu dung lượng; chưa có runtime iOS 15 để kiểm tra baseline.
