# Smart Printer Tech Stack Lab — thiết kế đề xuất

Ngày: 22/10/2026. Trạng thái: **chờ review, chưa triển khai**.

## Mục tiêu và lựa chọn đã xác nhận

Tạo app iOS để trực tiếp thử công nghệ tìm máy in, in, nhập tài liệu, sửa PDF/ảnh và scan. Người dùng đã chọn **native Apple trước + so sánh một số thư viện trong research**. Đây là app phục vụ đánh giá kỹ thuật; mỗi công cụ có tên stack, điều kiện hỗ trợ và kết quả thao tác để dễ thử.

Căn cứ: [Research Smart Printer cho iOS](../../smart-printer-ios-research.md). Project hiện tại là UIKit template, app target iOS 15.0, iPhone/iPad; chưa có luồng nghiệp vụ. Unit-test target đang đặt iOS 26.4. Giữ thay đổi project có sẵn của người dùng.

## Cách tiếp cận

| Phương án | Đánh đổi | Quyết định |
|---|---|---|
| Native trước, thêm một cropper và một editor để đối chiếu | Có baseline ít dependency, vẫn test được lựa chọn ngoài Apple | Chọn |
| Tích hợp mọi SDK ngay | Phụ thuộc model máy in, license, OS/toolchain; khó xác định nguyên nhân lỗi | Hoãn |
| Chỉ native | Gọn nhưng thiếu phần so sánh thư viện đã yêu cầu | Không chọn |

App chỉ có **3 tab: Printer, Scan, File**. Mỗi tab dùng navigation riêng; file đã nhập hoặc scan lưu chung để chuyển giữa các tab. UI dạng danh sách công cụ, preview và toolbar hệ thống; tiếng Việt cho mô tả, giữ tên tab theo yêu cầu. Có bộ file mẫu offline để test khi chưa có máy in/camera.

## Tab Printer

- Chọn/tìm máy in bằng `UIPrinterPickerController`; đây là picker hệ thống, không phải danh sách discovery tự xây.
- Xem tên/model, URL và color/duplex sau khi `contactPrinter` thành công. Lưu URL máy đã chọn bằng UserDefaults; luôn kiểm tra lại khi sử dụng.
- Chọn PDF/ảnh từ thư viện chung → preview → `UIPrintInteractionController` với các tùy chọn hệ thống và capability thực tế của máy.
- Ảnh chọn nhiều được ghép thành một PDF trước khi in để có thứ tự và lựa chọn trang nhất quán. Có trang mẫu A4/Letter, thước kiểm tra kích thước và ảnh portrait/landscape.
- In trực tiếp tới máy đã chọn là một thao tác riêng, có xác nhận nội dung trước khi gửi. Phân biệt lỗi, người dùng hủy, và kết quả callback của UIKit; callback không chứng minh giấy đã in đúng.
- Công cụ bổ sung sau baseline: tìm service `_ipp._tcp`/`_ipps._tcp` bằng `NWBrowser`, hiển thị endpoint/TXT để đối chiếu với picker. Nhãn rõ “phát hiện service”, không tự coi đó là máy in tương thích.

## Tab Scan

- `VNDocumentCameraViewController`: scan nhiều trang, review, xuất PDF/ảnh vào thư viện chung, mở sửa hoặc chuyển sang in.
- Kiểm tra `isSupported` và quyền camera; có đường sang Settings hoặc chọn ảnh từ thư viện khi không scan được.
- OCR bằng `VNRecognizeTextRequest` trên ảnh/scan/PDF render theo trang; hiển thị text, ngôn ngữ hỗ trợ và thời gian xử lý; copy/export TXT. Kiểm tra tiếng Việt/Anh trên OS đang chạy, không mặc định cả hai luôn được hỗ trợ.
- iOS 16+: thử PDFKit searchable PDF và live text/barcode qua `DataScannerViewController`. iOS 15 dùng camera scan + OCR text riêng; không gắn nhãn searchable PDF cho file chỉ có ảnh.
- iOS 26+: thử `RecognizeDocumentsRequest` trên cùng ảnh để đối chiếu text/bảng với OCR thường; OS thấp hơn giữ OCR thường và giải thích giới hạn.
- Không điều khiển flatbed/ADF của máy đa năng trong phạm vi này.

## Tab File — nhập từ nhiều nguồn

| Nguồn | Cách triển khai | Điều kiện/giới hạn |
|---|---|---|
| On My iPhone/iPad, iCloud Drive | Document picker, chọn nhiều file | Chờ file cloud tải xong trước khi báo đã nhập |
| Google Drive, Dropbox, OneDrive, Box… | File Provider trong Files | Dịch vụ phải được cài, đăng nhập và bật provider; không có OAuth riêng |
| SMB/NAS, ổ USB/thẻ nhớ | Những location mà Files cung cấp | Phụ thuộc kết nối và location thực tế của thiết bị |
| Photos | `PHPickerViewController`, chọn nhiều ảnh | Không xin quyền đọc toàn bộ thư viện |
| Scan/camera | Kết quả từ tab Scan | Dùng chung thư viện, không tạo kho scan riêng |
| Open In / mở bằng app từ bên ngoài | Document types + SceneDelegate nhận URL, cả cold/warm launch | Chỉ những định dạng đã khai báo và app nguồn cho phép |
| Share từ Mail/Gmail/Messages/Safari/app khác | Share Extension nhận PDF, ảnh, text, URL qua item providers | Chỉ nhận nội dung app nguồn chia sẻ; không đọc mailbox |
| Clipboard | Nút Dán do người dùng bấm | Nhận ảnh/text/URL; không tự đọc clipboard khi mở app |
| Drag & drop | `UIDropInteraction`, đặc biệt trên iPad | Copy file/ảnh được cung cấp, kiểm tra item provider |
| Link tải file HTTPS | `URLSessionDownloadTask` | Link tải trực tiếp; kiểm tra HTTP status, kích thước và nội dung thực |
| Website | `WKWebView` → print formatter/PDF renderer | Trang đăng nhập/nội dung động/CSS phân trang cần thử riêng |
| Text/HTML và contact | Text editor hoặc contact picker → PDF của app | Contact chỉ gồm trường người dùng chọn; không đọc cả danh bạ |

Thư viện hiển thị tên, định dạng, dung lượng; tìm theo tên, đổi tên, xóa có xác nhận, share và export qua Files. Các nguồn đi qua cùng đường nhập, mỗi file được báo thành công/thất bại riêng.

Giới hạn ban đầu cho link tải và Share Extension: **100 MiB/file**; download timeout request **60 giây**, chỉ HTTPS kể cả redirect. Kiểm tra cả byte thực khi server không cung cấp Content-Length. Files/Photos vẫn cần kiểm tra tài nguyên và xử lý thiếu dung lượng; không tự giải nén archive hoặc tải toàn bộ attachment vào một Data lớn. App Group inbox có ID ổn định để retry sau crash không nhập trùng.

### Định dạng và chỉnh sửa

- **PDF:** PDFKit preview/thumbnails; xoay, xóa, đổi thứ tự, crop box, ghép nhiều tài liệu, tách theo trang; Quick Look markup cơ bản và lưu bản sao. Không raster hóa toàn bộ PDF để sửa trang. Khóa/cấm sửa/cấm in được xử lý rõ trước thao tác.
- **Ảnh:** JPEG/PNG/HEIC khi decoder hệ thống hỗ trợ; crop, xoay, flip, resize, brightness/contrast, grayscale/B&W bằng Core Image/Core Graphics; Quick Look markup khi có hỗ trợ. Chuẩn hóa orientation, preview downsample bằng Image I/O, export từ nguồn đủ độ phân giải. File ảnh động/RAW ngoài bộ định dạng này chỉ preview nếu hỗ trợ, không hứa chỉnh sửa.
- **Text:** tạo/sửa TXT, chuyển thành PDF có phân trang.
- **Office/iWork và định dạng khác:** thử import/Quick Look khi `canPreview` cho phép; không bật nút sửa/in nếu chưa có đường chuyển đổi phù hợp.
- Mọi edit lưu thành tài liệu kết quả mới; file nhập ban đầu không bị ghi đè. Hủy edit không sinh kết quả giả. Crop PDF không phải redaction; nét ký/markup không phải chữ ký số và không sửa chữ gốc của PDF.

## Các stack để so sánh

| Bài test | Baseline | Stack bổ sung |
|---|---|---|
| Crop/rotate ảnh | Core Graphics/Core Image + UI nhỏ | Mantis v3.1.0 |
| Markup/editor ảnh | Quick Look + bộ chỉnh ảnh native | ZLImageEditor 3.0.0 |
| OCR | Vision OCR | PDFKit OCR export iOS 16+, RecognizeDocumentsRequest iOS 26+ |
| Tìm máy in | UIKit picker | Bonjour NWBrowser, chỉ discovery |

Mantis và ZLImageEditor là hai ứng viên từ research; đã đọc lại manifest các tag trên, **chưa build package**. Pin phiên bản khi triển khai và kiểm tra license/resources. Nếu build không đạt với Xcode 26.4/iOS 15, ghi rõ blocker và giữ baseline chạy được, không tự nâng deployment target. Không thêm cả TOCropViewController lẫn Mantis cho cùng một bài test.

Trong tab File, mở cùng ảnh gốc bằng từng editor; output đặt tên riêng rồi preview/share/print như tài liệu thông thường. Ghi thời gian xử lý/export, pixel/kích thước file và lỗi; thời gian người dùng thao tác editor không được coi là benchmark thuật toán. Ghi model/OS/phiên bản stack và bộ input khi lưu kết quả test; memory peak đo bằng Instruments khi kiểm tra phần cứng, không xây hệ thống telemetry.

## Kiến trúc và dữ liệu

- Giữ UIKit, dùng `UITabBarController` + ba `UINavigationController`, cấu hình root trong SceneDelegate; bỏ tham chiếu Main storyboard khi chuyển sang root bằng code, giữ LaunchScreen.
- Một `DocumentStore` dùng FileManager cho thư viện nhỏ; không thêm database/backend. Mỗi tài liệu có thư mục UUID và tên file riêng để chống trùng. Liệt kê từ filesystem; chưa cần history/query metadata có quan hệ.
- Tài liệu người dùng chọn lưu trong Documents; thumbnail ở Caches; file staging/intermediate ở tmp hoặc thư mục staging cùng volume khi cần atomic move. Chỉ công bố kết quả sau khi ghi/đọc lại thành công. Không giữ bản duy nhất của tài liệu trong cache/tmp.
- Share Extension dùng App Group inbox bền; copy item provider URL trước khi callback hết hạn. App nhận inbox khi foreground, chỉ dọn inbox sau khi import thành công. Extension không cưỡng ép mở app bằng API không được hỗ trợ.
- Document picker/external URL dùng security scope và coordinated I/O khi cần; copy vào kho app trước khi xử lý lâu. Không giữ URL ngoài sandbox thô để dùng lại.
- UI trên main actor; OCR, decode, PDF export và file I/O nặng được tách khỏi UI, xử lý từng trang, có progress/cancel. Không truyền một PDFDocument đang sửa giữa các luồng đồng thời.
- Xin camera ở đúng thao tác; Local Network/Bonjour chỉ thêm khi bật custom discovery. Không yêu cầu quyền Photos toàn bộ chỉ để chọn ảnh. Không bật ATS toàn app hoặc bỏ xác minh TLS.
- Dùng system controls, semantic colors, Dynamic Type, VoiceOver labels; hỗ trợ dark mode, xoay và popover anchor trên iPad.

## Hoàn tất và giới hạn

Hoàn tất khi thử được **import → edit → lưu → in**, **scan → PDF → edit → in**, nhận file ngoài app lúc cold/warm launch, và so sánh native/thư viện trên cùng input. Kết quả phải tồn tại sau mở lại app; hủy/lỗi/thiếu dung lượng không làm mất file gốc.

Kiểm tra iOS 15 baseline nếu có runtime/thiết bị; nhánh iOS 16 và 26 chạy trên OS tương ứng. API mới đặt `@available` trên helper và `#available` tại caller, có fallback đã mô tả. Không nâng toàn bộ app chỉ để dùng API mới.

Hoãn SDK Brother/Epson, IPP client riêng, Bluetooth/USB printing, network scanning, SDK PDF thương mại, sửa nội dung PDF gốc, redaction/chữ ký số, cloud OAuth riêng và backend conversion. Các mục này cần model/license hoặc yêu cầu chuyên biệt. Không thêm account, subscription, analytics hay template marketplace.

Simulator kiểm tra được nhiều luồng UI/file nhưng chưa chứng minh camera, discovery, chất lượng giấy in, OCR tiếng Việt và dung lượng thực tế. Cần iPhone/iPad + printer AirPrint để kết luận.

## Nguồn kỹ thuật

- [UIKit printing](https://developer.apple.com/documentation/uikit/uiprintinteractioncontroller), [Document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller), [VisionKit scanner](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller), [PDFKit](https://developer.apple.com/documentation/pdfkit): đối chiếu lại tài liệu Apple ngày lập plan.
- [Mantis v3.1.0 manifest](https://github.com/guoyingtao/Mantis/blob/v3.1.0/Package.swift), [ZLImageEditor 3.0.0 manifest](https://github.com/longitachi/ZLImageEditor/blob/3.0.0/Package.swift): ứng viên cho giai đoạn so sánh, không phải xác nhận build thành công.
- Guidance Axiom: axiom-design, axiom-uikit, axiom-data, axiom-media, axiom-vision, axiom-networking, axiom-concurrency, axiom-integration và axiom-apple-docs. Quyết định scope theo yêu cầu người dùng và research trong repo.
