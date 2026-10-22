# Research Smart Printer cho iOS

Ngày nghiên cứu: **22/10/2026** · Storefront đối chiếu: **US** · Ngôn ngữ báo cáo: tiếng Việt.

## 1. Kết luận để chọn tech stack

**Có thể làm bộ tính năng cốt lõi bằng framework Apple:** in qua AirPrint, chọn máy in, scan tài liệu bằng camera, nhập ảnh/file, xử lý ảnh, xem và thao tác trang PDF, markup, lưu và chia sẻ tài liệu. Với project hiện tại, nên giữ UIKit và hỗ trợ **iOS 15.0**, chưa cần thêm SDK in hoặc thư viện scan.

| Nhu cầu | Lựa chọn đề xuất | Phần cần tự làm / giới hạn |
|---|---|---|
| In PDF, ảnh | UIKit `UIPrintInteractionController` | Chuẩn bị nội dung; máy in cần tương thích AirPrint |
| Tìm/chọn máy in | `UIPrinterPickerController` | Dùng UI hệ thống trước; danh sách tùy biến là phạm vi khác |
| Scan giấy bằng camera | VisionKit `VNDocumentCameraViewController` | Ghép ảnh thành PDF, lưu, đặt tên; scan không tự tạo PDF |
| OCR ảnh scan | Vision `VNRecognizeTextRequest` | Kiểm tra ngôn ngữ trên OS thực tế; quản lý kết quả OCR |
| PDF tìm kiếm được | iOS 16+: PDFKit `saveTextFromOCROption` | iOS 15: lưu text riêng hoặc tự tạo lớp text ẩn |
| Xem, ghép/tách/xoay/sắp xếp PDF | PDFKit | UI chọn trang, lịch sử sửa, xử lý file lỗi |
| Markup cơ bản | Quick Look editing | Lưu bản chỉnh sửa qua delegate; ít tùy biến UI |
| Crop/xoay/filter ảnh | Core Image + Core Graphics/Image I/O | Apple cung cấp xử lý, không cung cấp trọn bộ UI như Photos |
| Crop UI có sẵn | TOCropViewController **hoặc** Mantis | Chỉ thêm một thư viện khi UI native/custom nhỏ không đủ |
| Nhập/xuất, cloud qua Files | `UIDocumentPickerViewController` | Chỉ thấy provider được cài/cấu hình; không đồng nghĩa có SDK Drive riêng |

Các lựa chọn trên là **đề xuất kỹ thuật**, không phải kết luận về framework nội bộ của các app tham khảo. Chi tiết API và nguồn ở mục 4–7.

Ba ranh giới ảnh hưởng trực tiếp đến phạm vi sản phẩm:

1. **AirPrint không phải driver cho mọi máy in.** Tên hãng, Wi-Fi hoặc việc tìm thấy một thiết bị chưa chứng minh in được trên model đó. Apple công bố điều kiện AirPrint và danh sách tra cứu model. [About AirPrint](https://support.apple.com/en-us/102895)
2. **Scan bằng camera khác scan từ máy đa năng.** Ảnh quảng bá của cả ba cho thấy camera scanner; chưa có bằng chứng đủ để kết luận chúng điều khiển flatbed/ADF qua mạng. Nguồn ảnh ở mục 3.
3. **Xem được file Office khác chuyển đổi/in được file Office.** Quick Look hỗ trợ preview nhiều định dạng, còn `canPrint(_:)` của UIKit cho URL yêu cầu PDF hoặc ảnh hỗ trợ bởi Image I/O. Cần xử lý riêng nếu hứa in DOCX/XLSX/PPTX với độ chính xác cao. [Quick Look](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller), [Kiểm tra khả năng in](https://developer.apple.com/documentation/uikit/uiprintinteractioncontroller/canprint(_:)-364vj)

## 2. Phương pháp, độ tin cậy và hiện trạng repo

### Phạm vi bằng chứng

- Đọc trang App Store, lịch sử phiên bản, website nhà phát triển và metadata iTunes Lookup của đúng ba App ID.
- Đối chiếu trực tiếp 18 screenshot quảng bá iPhone; screenshot là bằng chứng về UI/tính năng được quảng bá, **không phải kiểm thử ứng dụng đang chạy**.
- Tra cứu tài liệu Apple/WWDC, kiểm tra khai báo trong SDK iOS 26.4 cài trên máy và repository/package/license chính thức của thư viện.
- Không cài app, mua gói, kiểm tra traffic, giải mã binary hoặc in/scan trên phần cứng.
- Không suy luận SDK nội bộ, khả năng offline hoặc chất lượng OCR của đối thủ chỉ từ mô tả.

Ký hiệu trong bảng tính năng: **M** = mô tả nhà phát triển; **V** = release notes; **S** = screenshot; **?** = chưa tìm thấy bằng chứng, không có nghĩa tính năng không tồn tại.

### Cơ sở phiên bản iOS

Đã đọc [project.pbxproj](../SmartPrinterTechStack/SmartPrinterTechStack.xcodeproj/project.pbxproj): target app `SmartPrinterTechStack` đặt `IPHONEOS_DEPLOYMENT_TARGET = 15.0` ở cả Debug và Release; `TARGETED_DEVICE_FAMILY = "1,2"` gồm iPhone/iPad. Project và unit-test có setting 26.4 riêng; không lấy chúng làm minimum OS của app. File project đã có thay đổi trước khi research; báo cáo không sửa file này.

SDK được kiểm tra tại `iPhoneOS26.4.sdk`, dưới `/Applications/Xcode.app`. Đây là SDK cài tại máy, không phải khẳng định phiên bản Apple mới nhất. API sau iOS 15 được tách thành lựa chọn có điều kiện ở mục 5.

Guidance đã sử dụng: Axiom `axiom-apple-docs`, `axiom-vision`, `axiom-media`, `axiom-networking`, `axiom-data`, `axiom-uikit` và `axiom-integration`; tài liệu Apple/GitHub được dẫn là nguồn để kiểm chứng độc lập.

## 3. Research ba ứng dụng

### 3.1. Đúng sản phẩm và phiên bản

| Mã | App / nhà phát triển | Phiên bản tại thời điểm tra cứu | Minimum iOS | Monetization công khai |
|---|---|---|---|---|
| A | [Printer App: Smart Print — Upscala Apps OU](https://apps.apple.com/us/app/printer-app-smart-print/id1585148293) | 2.2.8 · 23/09/2026 | 16.0 | Free + IAP; một số tính năng cần subscription |
| B | [Smart Printer App℠ for HP · — AstraBridge Limited](https://apps.apple.com/us/app/smart-printer-app-for-hp/id6757393880) | 1.2.4 · 14/10/2026 | 15.6 | Free + IAP; có Premium và lifetime |
| C | [Printer app ® — SMM service, s.r.o.](https://apps.apple.com/us/app/printer-app/id1541008027) | 1.7.2 · 04/06/2026 | 15.0 | Free + IAP; subscription và SKU photo editor |

Phiên bản/minimum OS/ngày release được đối chiếu thêm bằng [Lookup A](https://itunes.apple.com/lookup?id=1585148293&country=us), [Lookup B](https://itunes.apple.com/lookup?id=6757393880&country=us), [Lookup C](https://itunes.apple.com/lookup?id=1541008027&country=us). Ngày trong bảng lấy phần ngày UTC của metadata. Tên app có thể đổi; dùng App ID để tránh nhầm sản phẩm.

### 3.2. Ma trận tính năng được công bố

| Tính năng | A | B | C |
|---|---|---|---|
| In ảnh, tài liệu | M | M | M |
| AirPrint | M | M | M |
| Nguồn nhập | Photos, Dropbox, Google Drive (M) | Photos, storage, cloud (M) | Photos, iCloud (M) |
| Định dạng được gọi tên | PDF, DOCX, PAGES, TXT (M) | PDF (M); Word/Excel/TXT (S) | PDF, XSL, DOCX (M) |
| Web / email / contacts | Web, contacts (M) | Web, email (M) | Web, contacts A4 (M) |
| Camera scanner | M/S | M/S, nhiều trang | S, scan-to-PDF |
| OCR lấy chữ | ? | V1.1.0 | ? |
| Sửa PDF | Highlight, draw, text (M) | Xóa trang, merge (M) | Crop/rotate/merge/split/annotate/reorder (V1.5.0) |
| Sửa ảnh | Filter, blur, resize, màu (M) | Crop/rotate/filter (M), collage (S) | Transform/filter/adjust/focus/sticker/text (S) |
| Copies / page range / paper | M | M/S | S |
| Duplex | M/S | S | ? |
| Nhiều trang/tờ | M/S | ? | Mục Layout (S), chưa rõ mức hỗ trợ |
| Printables | Cards/planners/calendars (S) | Labels/stickers/coloring/calendar (M) | ? |
| Quản lý tài liệu | ? | Files/recent prints (S) | Local storage/filter/grid/list (M), folders (S) |
| Ghi nhớ máy in / đổi tên | ? | Mapping mạng–printer, tên trùng (V) | ? |
| Scanner vật lý qua mạng | ? | ? | ? |

Nguồn M/V: trang App Store tương ứng ở mục 3.1. Nguồn S theo từng nhóm màn hình:

- A: [dashboard/printables](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/07/19/16/0719168f-e403-3fde-3fba-34134eba0af2/b1ee5aba-e519-4b90-9905-e7792f77459b_53.jpg/392x696bb.jpg), [scan camera](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/9a/07/e6/9a07e603-5826-e537-f27b-96dd7efa54aa/d92f2ec7-d90c-4f89-8e2f-dc4e4664bfea_56.jpg/392x696bb.jpg), [print options](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/92/64/77/92647714-129c-3d32-ff63-60227cf24d52/e35f626d-c2df-4626-93ef-219cfa47178c_59.jpg/392x696bb.jpg).
- B: [dashboard](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/6e/1c/9d/6e1c9de4-8529-3bbe-54f1-e642551a74d8/3.jpg/1000x1500bb.jpg), [print options](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/4f/3d/5d/4f3d5da6-4440-434c-a932-c6308811d16c/1.jpg/1000x1500bb.jpg), [scan camera](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/08/73/78/0873780c-7976-4ca1-c126-e8f44c8620de/3.jpg/320x480bb.jpg), [collage](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/37/40/0c/37400cfb-adfd-1590-2fa0-37752b653d73/4.jpg/320x480bb.jpg).
- C: [scan camera](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/f9/92/dc/f992dc6d-35fd-9101-43a1-b07c3d8bd091/c228a4ed-3216-477b-ab25-3c811e8bddc7_3.jpg/392x696bb.jpg), [photo editor](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/22/84/d1/2284d1b4-7fba-8119-1ff5-c662df877329/5a525dad-ae9b-4791-8a91-aa5d55032c7d_4.jpg/392x696bb.jpg), [files/folders](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/fb/60/e6/fb60e6c4-c918-9fb4-faa8-eea16ec4a4c5/80e9a203-a80c-44bb-bacc-a7236f2b0b54_5.jpg/392x696bb.jpg), [print layout](https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/82/55/07/825507b3-f964-4727-1f77-05f34166d3d6/ee97e22a-e7ab-49aa-914f-a7ba810c7537_2.jpg/392x696bb.jpg).

### 3.3. Những chi tiết ảnh hưởng đến yêu cầu

**A:** định vị xoay quanh chuẩn bị nội dung trước khi in. Screenshot print options có N-up 1/2/4/6/9/16, orientation, duplex và tùy chọn annotations. [Website chính thức](https://www.airprinter.app/) và listing dùng số lượng máy in khác nhau; không lấy các con số marketing làm kết quả kiểm thử tương thích. Điều kiện kỹ thuật được công bố là AirPrint.

**B:** tên có HP nhưng developer là AstraBridge, không phải HP. Release 1.1.0 công bố OCR; lịch sử còn đề cập crop preview, rung hoàn tất và quản lý tên máy trùng. Bluetooth chỉ xuất hiện trong quảng cáo, chưa có bằng chứng về transport/model được hỗ trợ. “Editable PDF” không chứng minh khả năng sửa nội dung chữ gốc. [Listing và lịch sử phiên bản B](https://apps.apple.com/us/app/smart-printer-app-for-hp/id6757393880)

**C:** release 1.5.0 ngày 02/06/2025 là nguồn cho bộ thao tác PDF; mô tả hiện tại không liệt kê đầy đủ. Giữ nguyên “XSL” như listing, không tự hiểu thành XLS/XLSX đã hỗ trợ. [Website developer](https://www.team2swift.com/) dẫn đúng App ID nhưng số lượng máy in khác screenshot; cũng chỉ nên xem là marketing.

### 3.4. Monetization và điều chưa xác minh

Giá US hiển thị khi tra cứu chỉ là các SKU công khai, không phải bản đồ paywall:

| App | Ví dụ IAP nhìn thấy | Không thể kết luận |
|---|---|---|
| A | My Printer: $7.49–$59.99; Printables $14.99 | Kỳ hạn từng SKU, số lượt in miễn phí |
| B | Premium nhiều mức; Lifetime $69.99 | Kỳ hạn mọi gói Premium; mô tả kỳ hạn có chỗ tự mâu thuẫn |
| C | SKU ghi tuần $9.99, tháng $14.99, năm $59.99 | Offer/trial hiện hành hoặc gói người dùng cụ thể sẽ thấy |

Nguồn: mục In-App Purchases của từng listing. Giá và offer có thể đổi theo quốc gia/tài khoản. Chưa xác minh gate từng tính năng, restore purchases, yêu cầu account hoặc hoạt động offline. Không lấy review người dùng làm bằng chứng chắc chắn về lỗi hay paywall hiện tại.

## 4. Ánh xạ tính năng sang công nghệ Apple

### 4.1. Print và tìm printer

**Luồng ít công nhất:** người dùng chọn PDF/ảnh → app mở print sheet → hệ thống tìm printer và cung cấp tùy chọn phù hợp thiết bị. `UIPrintInteractionController` nhận một nguồn nội dung: `printingItem`, `printingItems`, `printFormatter` hoặc `printPageRenderer`. Không cần triển khai giao thức in cho luồng này. [UIPrintInteractionController](https://developer.apple.com/documentation/uikit/uiprintinteractioncontroller)

| Việc cần làm | API / cách làm | Giới hạn cần thể hiện trong sản phẩm |
|---|---|---|
| In một PDF/ảnh | `printingItem` + kiểm tra `canPrint(_:)` | PDF khóa/cấm in hoặc file lỗi có thể bị từ chối |
| Chọn máy in trước khi chọn file | `UIPrinterPickerController` | Picker hệ thống; không phải một `UIViewController` để gọi `present` như VC thông thường |
| Ghi nhớ máy đã chọn | Lưu `UIPrinter.url`; khởi tạo lại `UIPrinter(url:)` | Có object không có nghĩa máy đang online |
| Đọc khả năng máy in | `contactPrinter`, `supportsColor`, `supportsDuplex`, `makeAndModel` | Máy tạo từ URL cần contact thành công trước khi tin capability |
| In lại tới máy đã chọn | `print(to:completionHandler:)` | Có API trực tiếp; vẫn cần hành động in rõ ràng của người dùng và xử lý lỗi |
| Preview, copies, page range, paper, duplex | Ưu tiên print sheet | Tùy OS, nội dung và capability; app không ép máy có tính năng phần cứng không tồn tại |
| Bố cục N-up, collage, ID card | Ghép nội dung thành trang PDF bằng Core Graphics/PDF renderer | Cần UI và thuật toán layout của app để đồng nhất từ iOS 15 |
| Booklet | Tạo thứ tự/trang trắng/bố cục riêng trước khi in | Khác N-up; phải kiểm chứng chiều duplex và lề |
| Nhận kết quả | Completion của UIKit | Ghi nhận trạng thái theo UIKit; không hứa xác nhận chất lượng từng tờ giấy |

Nguồn: [Printer picker](https://developer.apple.com/documentation/uikit/uiprinterpickercontroller), [UIPrinter](https://developer.apple.com/documentation/uikit/uiprinter), [In trực tiếp](https://developer.apple.com/documentation/uikit/uiprintinteractioncontroller/print(to:completionhandler:)), [Completion](https://developer.apple.com/documentation/uikit/uiprintinteractioncontroller/completionhandler), [PDF renderer](https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer).

Hai chi tiết dễ bỏ sót trong SDK 26.4: `printingItems` không hỗ trợ page range như một tài liệu nhiều trang; nếu cần chọn trang xuyên nhiều ảnh, nên tạo một PDF. `showsPageRange` đã deprecated từ iOS 10, không dùng nó làm nền tảng điều khiển UI. Header cũng ghi `contactPrinter` có thể mất tới 30 giây; UI cần trạng thái đang kiểm tra. [API print controller](https://developer.apple.com/documentation/uikit/uiprintinteractioncontroller), header `UIKit.framework/Headers/UIPrintInteractionController.h` và `UIPrinter.h` trong SDK đã nêu ở mục 2.

**Custom discovery chỉ khi có yêu cầu cụ thể:** `NWBrowser` browse `_ipp._tcp` / `_ipps._tcp`, theo dõi thiết bị xuất hiện/mất kết nối, resolve endpoint và đọc TXT/capability cần thiết. Bonjour phát hiện service, không cung cấp driver hay tự đảm bảo printer nhận được PDF. Nếu kết nối IPP trực tiếp, phải thương lượng `document-format-supported`, xử lý job/error/cancel và khác biệt thiết bị. [NWBrowser](https://developer.apple.com/documentation/network/nwbrowser), [IANA IPP/IPPS](https://www.iana.org/assignments/service-names-port-numbers?search=ipp), [PWG IPP Guide](https://www.pwg.org/ipp/ippguide.html)

**Phạm vi tương thích nên công bố:** máy AirPrint trong điều kiện mạng được hỗ trợ và model đã thử. Không hứa in USB/Bluetooth bất kỳ. Máy non-AirPrint là nhánh riêng, cần danh sách model và SDK/giao thức được xác minh; xem mục 6.

### 4.2. Scan document bằng camera

`VNDocumentCameraViewController` có sẵn UI scan nhiều trang, nhận diện mép, crop/chỉnh phối cảnh và bước review. Kết quả delegate là `VNDocumentCameraScan`, lấy **ảnh từng trang**, sau đó app tạo PDF bằng PDFKit hoặc `UIGraphicsPDFRenderer`. Kiểm tra `isSupported` trước khi mở; xử lý cancel/error và quyền camera. [VisionKit document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller)

Luồng đề xuất: scan → lấy ảnh từng trang → lưu bản làm việc → đặt tên/sắp xếp trang → tạo PDF → preview → share hoặc print. Không cần AVFoundation/custom camera chỉ để có scanner cơ bản.

Nếu cần overlay hoàn toàn riêng hoặc auto-capture theo quy tắc riêng, mới đánh giá custom camera + Vision detect document/rectangle + Core Image perspective correction. Chi phí tăng ở ổn định khung, lấy nét, ánh sáng, xoay máy và chất lượng ảnh; không chọn hướng này chỉ để đổi màu giao diện scanner. [Vision](https://developer.apple.com/documentation/vision), [Geometry filters](https://developer.apple.com/documentation/coreimage/geometry-adjustment-filters)

**Không dùng document camera để điều khiển scanner MFP.** Trong SDK 26.4, `ImageCaptureCore/ICScannerDevice.h` đánh dấu `ICScannerDevice` là `IC_UNAVAILABLE(ios)`, dù framework có một số API camera trên iOS. Nếu cần flatbed/ADF qua mạng, phải nghiên cứu riêng eSCL hoặc SDK hãng và thử từng model. Mopria công bố eSCL cho client scanner; chưa triển khai/kiểm chứng giao thức này trong research. [ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore), [eSCL specification](https://mopria.org/spec-download)

### 4.3. OCR, text extraction và PDF tìm kiếm

| Bài toán | Native path | Điều phải kiểm chứng |
|---|---|---|
| Lấy text từ ảnh/scan | `VNRecognizeTextRequest`, ưu tiên `.accurate` cho tài liệu | Ngôn ngữ, confidence, chiều ảnh, dấu tiếng Việt |
| Lấy text từ PDF đã có text | `PDFPage.string` / PDFKit selection/search | Có text layer thật hay chỉ bitmap; thứ tự đọc |
| Chọn/copy text trong PDF scan | Live Text của PDFKit trên iOS 16+ | Khác việc lưu text layer vào file để app khác dùng |
| Xuất PDF scan có text ẩn | iOS 16+: `PDFDocumentWriteOption.saveTextFromOCROption` | OS/ngôn ngữ và chi phí OCR nhiều trang |
| Cùng tính năng trên iOS 15 | Vision OCR + tự vẽ text ẩn qua Core Graphics | Ánh xạ tọa độ/font/rotation; nhiều việc hơn chỉ ghép ảnh |
| Chỉ cần tìm kiếm trong thư viện app | Lưu OCR text riêng cạnh tài liệu | File PDF xuất ra chưa tự trở thành searchable PDF |
| Đọc bảng/list/cấu trúc | iOS 26+: `RecognizeDocumentsRequest` | Không phải converter PDF→Word/Excel bảo toàn layout |

Nguồn: [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), [PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage), [PDFKit WWDC22](https://developer.apple.com/videos/play/wwdc2022/10089/), [Save OCR text](https://developer.apple.com/documentation/pdfkit/pdfdocumentwriteoption/savetextfromocroption), [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest).

Không hardcode kết luận “Vision đọc tốt tiếng Việt trên mọi máy iOS 15”. Gọi `supportedRecognitionLanguages()` cho request/revision đang chạy rồi benchmark bằng tài liệu thật: hóa đơn, dấu tiếng Việt, bảng, chữ nhỏ, ảnh mờ. OCR plain text không giữ nguyên bố cục Office. [OCR language API](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)

`DataScannerViewController` dành cho nhận diện text/barcode trực tiếp qua camera, không thay thế scanner tài liệu nhiều trang. Chỉ dùng nếu có nhu cầu live text/QR và đã kiểm tra `isSupported` + `isAvailable`. [DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller)

### 4.4. Edit ảnh

| Công cụ | Framework Apple | Có sẵn UI hoàn chỉnh? |
|---|---|---|
| Crop, rotate, scale, flip | Core Graphics/Core Image | App tự làm điều khiển, hoặc chọn crop library |
| Chỉnh phối cảnh | `CIPerspectiveCorrection` | Tự làm bốn điểm điều khiển nếu cần edit thủ công |
| Brightness/contrast/saturation/exposure | Core Image filters | Tự làm slider/preset |
| Gray/B&W, sharpen, blur | Core Image filters | Tự làm preview và giá trị mặc định |
| Thêm text/sticker/watermark | Core Graphics + UIKit layout | Tự quản lý vị trí, scale và export |
| Vẽ tay/chữ ký dạng nét | PencilKit `PKCanvasView` | Canvas/tool picker native; app lo lưu và ghép vào ảnh/PDF |
| Markup nhanh ảnh/PDF | Quick Look editing | Có UI hệ thống, phù hợp nhu cầu ít tùy biến |
| Downsample/encode ảnh | Image I/O | Không phải editor UI |

Nguồn: [Core Image](https://developer.apple.com/documentation/coreimage), [Geometry filters](https://developer.apple.com/documentation/coreimage/geometry-adjustment-filters), [PKCanvasView](https://developer.apple.com/documentation/pencilkit/pkcanvasview), [Quick Look editing](https://developer.apple.com/documentation/quicklook/qlpreviewcontrollerdelegate/previewcontroller(_:editingmodefor:)).

`PHPickerViewController` giải quyết **chọn ảnh**, không cung cấp toàn bộ editor như app Photos. Ưu tiên lấy ảnh qua picker thay vì yêu cầu đọc cả thư viện. Giữ ảnh gốc và thông số chỉnh sửa để tránh encode JPEG lặp lại; tạo preview ở độ phân giải phù hợp, export riêng theo chất lượng in. [Photos picker](https://developer.apple.com/documentation/photosui/phpickerviewcontroller), [Image I/O](https://developer.apple.com/documentation/imageio)

Nếu chỉ cần crop UI tốt, thư viện crop là khoảng trống hợp lý để dùng GitHub. Đừng thêm cả bộ editor lớn chỉ để có rotate/filter mà Core Image đã xử lý được. Collage/N-up vẫn cần layout trang của app, không tự xuất hiện khi thêm thư viện crop.

### 4.5. PDF và document

**PDFKit đủ cho phần lớn thao tác trang:** `PDFView`/`PDFThumbnailView` để xem, `PDFDocument` để đọc/ghi/insert/remove/exchange page, `PDFPage.rotation` để xoay, annotation để highlight/ink/free text/widget. Merge/split là thao tác trên tập trang, không cần SDK trả phí chỉ vì tên tính năng này. [PDFKit](https://developer.apple.com/documentation/pdfkit), [Thao tác trang](https://developer.apple.com/documentation/pdfkit/pdfdocument/insert(_:at:)), [PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage)

**Markup có sẵn trước khi tự xây editor:** Quick Look cho phép bật `.createCopy` hoặc `.updateContents`, rồi nhận file đã sửa qua delegate. Bộ edit hỗ trợ tùy loại file/OS; hình thức này phù hợp annotate cơ bản và ít tùy biến. Cần xử lý cả callback tạo bản sao, kể cả khi yêu cầu sửa tại chỗ. [Quick Look editing delegate](https://developer.apple.com/documentation/quicklook/qlpreviewcontrollerdelegate/previewcontroller(_:editingmodefor:))

Nếu cần toolbar/selection/undo theo thiết kế riêng, dùng PDFKit annotation + UIKit; PencilKit hỗ trợ stroke input. Trên iOS 26+, PaperKit cung cấp canvas markup gồm drawing, shapes, images và text boxes, nhưng app vẫn lo liên kết với trang PDF và xuất bản in. [PencilKit](https://developer.apple.com/documentation/pencilkit/pkcanvasview), [Meet PaperKit](https://developer.apple.com/videos/play/wwdc2025/285/)

Các giới hạn không nên gộp vào một nút “Edit document”:

- **Annotation khác sửa chữ gốc:** thêm text box/highlight không tương đương chỉnh paragraph/font/layout có sẵn trong PDF. Apple phân biệt nội dung trang và annotations trong [PDFKit WWDC22](https://developer.apple.com/videos/play/wwdc2022/10089/).
- **Chữ ký vẽ tay khác chữ ký số PDF:** ảnh/nét ký không tự có chứng thư, xác minh tính toàn vẹn hoặc quy trình ký số.
- **Crop khác redaction:** đổi crop box hoặc đè một hình chữ nhật có thể để nội dung gốc còn trong file. Nếu yêu cầu xóa dữ liệu thật, cần giải pháp redaction và kiểm chứng riêng.
- **PDF widget khác tự phát hiện mọi form:** PDFKit đọc/thêm widget không đồng nghĩa nhận mọi form ảnh scan thành trường nhập liệu. [PDF widgets](https://developer.apple.com/documentation/pdfkit/adding-widgets-to-a-pdf-document)
- **Preview Office khác export:** Quick Look có thể preview iWork/Office; không thấy public API tổng quát từ Quick Look để chuyển mọi định dạng sang PDF có layout bảo đảm. MVP nên nhận PDF/ảnh/text trước, hướng dẫn export Office sang PDF, hoặc đánh giá SDK chuyển đổi khi yêu cầu đã rõ.

### 4.6. Files, cloud, web, email, contacts và printables

| Nhóm | Cách ưu tiên built-in | Phần không tự có |
|---|---|---|
| Import/export nhiều file | `UIDocumentPickerViewController` + Uniform Type Identifiers | Xác thực định dạng/file lỗi; tải file cloud chưa có local |
| iCloud Drive / Google Drive / Dropbox qua Files | Document picker và File Provider của dịch vụ | Không tương đương duyệt account cloud trực tiếp bên trong app |
| Quản lý tài liệu local | FileManager; Core Data nếu cần metadata/query/thư mục/history có cấu trúc | UI, rename, search, lifecycle, kiểm soát dung lượng |
| Xem nhiều loại file | `QLPreviewController` + `canPreview` | Không đảm bảo có converter hoặc editor cho loại đó |
| In website/HTML | `WKWebView.viewPrintFormatter()` + print renderer; `createPDF` khi cần PDF | Phân trang, CSS, nội dung động/login phải thử |
| In email/attachment | Nhận nội dung/file qua share/import | Không có public API đọc hộp thư Apple Mail tùy ý |
| In contact | `CNContactPickerViewController` → bố cục PDF của app | Cần thiết kế các trường được in, tránh in dư dữ liệu |
| Text/note để in | `UITextView`/attributed text → print formatter/PDF | Công cụ edit và phân trang |
| Cards/planners/labels/ID/collage | Template PDF + Core Graphics | Nội dung template, kích thước, bản quyền và calibration |
| Chia sẻ | `UIActivityViewController` / document export | App đích quyết định tác vụ nhận được |

Nguồn: [Document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller), [File Provider và thư mục ngoài sandbox](https://developer.apple.com/documentation/uikit/providing-access-to-directories), [Quick Look](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller), [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [Web PDF](https://developer.apple.com/documentation/webkit/wkwebview/createpdf(configuration:completionhandler:)), [Contact picker và quyền truy cập](https://developer.apple.com/videos/play/wwdc2024/10121/), [PDF renderer](https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer).

Với file ngoài sandbox, quản lý security-scoped access và phối hợp đọc/ghi; đừng lưu một URL thô rồi giả định lần sau còn quyền. Nếu chọn nhập bản sao vào thư viện app, xử lý đọc thành công trước khi báo đã import. Cloud provider có thể không sẵn sàng hoặc cần tải file. [External documents](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)

Trên iOS 15, Core Data là lựa chọn native hợp lệ cho metadata có truy vấn. Chưa cần database chỉ để lưu vài URL máy in; dùng UserDefaults cho preference nhỏ. Lưu PDF/ảnh thành file, không nhét bitmap lớn vào UserDefaults. SwiftData cần iOS 17+, nên không dùng làm baseline của app này. [Core Data](https://developer.apple.com/documentation/coredata), [SwiftData](https://developer.apple.com/documentation/swiftdata)

## 5. Ma trận availability cho target iOS 15

| API / khả năng | Mốc cần biết | Cách dùng trong app này |
|---|---|---|
| UIPrintInteractionController | iOS 4.2+ | Dùng baseline |
| UIPrinter / UIPrinterPickerController | iOS 8+ | Dùng baseline |
| PDFKit trên iOS | iOS 11+ | Dùng baseline cho page/annotation APIs phù hợp |
| UIGraphicsPDFRenderer | iOS 10+ | Dùng baseline |
| VNDocumentCameraViewController | iOS 13+ | Baseline + kiểm tra hardware `isSupported` |
| VNRecognizeTextRequest | iOS 13+ | Baseline; query language support theo revision |
| PHPickerViewController | iOS 14+ | Phù hợp UIKit/iOS 15 |
| Quick Look markup editing mode | iOS 13+ | Baseline + callback lưu file |
| NWBrowser | iOS 13+ | Chỉ thêm nếu cần custom discovery |
| PencilKit canvas | iOS 13+ | Baseline nếu cần custom drawing |
| WKWebView.createPDF | iOS 14+ | Baseline; kiểm chứng pagination |
| PDFKit OCR export / burn-in annotations | iOS 16+ | `if #available(iOS 16.0, *)`; iOS 15 tự render nếu thật sự cần |
| DataScannerViewController | iOS 16+ và hardware hỗ trợ | Gate OS + `isSupported/isAvailable`; fallback scan ảnh rồi OCR |
| PhotosPicker trong SwiftUI | iOS 16+ | Nếu dùng về sau, gate; UIKit baseline vẫn PHPicker |
| PDFKit JPEG/optimize image write options | iOS 16.4+ | `if #available(iOS 16.4, *)`; iOS 15 tự tối ưu ảnh khi tạo PDF |
| SwiftData | iOS 17+ | Nếu áp dụng: gate và persistence fallback; hiện chọn Core Data khi cần |
| RecognizeDocumentsRequest | iOS 26+ | `if #available(iOS 26.0, *)`; fallback VNRecognizeTextRequest, không hứa cấu trúc bảng tương đương |
| PaperKit | iOS 26+ | `if #available(iOS 26.0, *)`; fallback Quick Look/PDFKit/PencilKit |

Các minimum quan trọng được kiểm tra thêm trong headers/interfaces SDK 26.4: `UIKit`, `VisionKit`, `Vision`, `PDFKit`, `PaperKit`. `PDFDocument.h` xác nhận OCR/burn-in từ iOS 16 và JPEG/optimize từ 16.4; `ICScannerDevice.h` xác nhận không hỗ trợ iOS. Đây là kiểm tra khai báo, chưa phải chạy trên các OS đó.

Nếu tách helper/class dùng API mới, đặt `@available(iOS 16.0, *)` hoặc `@available(iOS 26.0, *)` tương ứng lên declaration và giữ gate tại caller. Runtime gate không giải quyết việc dependency yêu cầu minimum iOS cao hơn target, hay compiler/SDK không chứa API đó. Không cần nâng minimum OS chỉ để có scanner/PDF/print cơ bản.

## 6. Thư viện GitHub và SDK ngoài khi native chưa đủ

### 6.1. Open source

Trạng thái dưới đây là snapshot 22/10/2026. Ngày release thể hiện hoạt động dự án, không chứng minh chất lượng hoặc tương thích máy in. Minimum lấy từ manifest/tag khi có; chưa build thư viện.

| Thư viện | Khoảng trống giải quyết | Tích hợp / minimum / license | Tình trạng và quyết định |
|---|---|---|---|
| [TOCropViewController](https://github.com/TimOliver/TOCropViewController) | UI crop, ratio, xoay | SPM; ObjC + Swift wrapper; [3.2.0: iOS 12+](https://github.com/TimOliver/TOCropViewController/blob/3.2.0/Package.swift); [MIT](https://github.com/TimOliver/TOCropViewController/blob/3.2.0/LICENSE) | [3.2.0 · 05/08/2026](https://github.com/TimOliver/TOCropViewController/releases/tag/3.2.0). **Ưu tiên nếu chỉ thiếu crop UI** |
| [Mantis](https://github.com/guoyingtao/Mantis) | Crop, straighten, flip, perspective UI | Swift/SPM; [v3.1.0: iOS 15+](https://github.com/guoyingtao/Mantis/blob/v3.1.0/Package.swift); [MIT](https://github.com/guoyingtao/Mantis/blob/v3.1.0/LICENSE) | [v3.1.0 · 09/07/2026](https://github.com/guoyingtao/Mantis/releases/tag/v3.1.0). **Chọn thay TOCrop nếu cần bộ crop rộng hơn**, không thêm cả hai |
| [ZLImageEditor](https://github.com/longitachi/ZLImageEditor) | Editor UI có draw/crop/mosaic/text và image stickers/filter/adjust | Swift/UIKit/SPM; [3.0.0: iOS 10+](https://github.com/longitachi/ZLImageEditor/blob/3.0.0/Package.swift), không có external package dependency; [MIT](https://github.com/longitachi/ZLImageEditor/blob/3.0.0/LICENSE) | [3.0.0 · 22/05/2026](https://github.com/longitachi/ZLImageEditor/releases/tag/3.0.0). **Đánh giá khi cần editor đầy đủ**; không thêm cropper khác nếu UI này đã đủ |
| [Brightroom](https://github.com/FluidGroup/Brightroom) | Engine/editor crop, filter, color, blur; UI SwiftUI có thể host trong UIKit | [5.1.2: iOS 17+, Swift tools 6.3](https://github.com/FluidGroup/Brightroom/blob/5.1.2/Package.swift); MIT, thêm StateGraph/Apache-2.0 | [5.1.2 · 27/09/2026](https://github.com/FluidGroup/Brightroom/releases/tag/5.1.2). **Hoãn cho target 15**; chưa thấy cam kết text/sticker trong UI được tài liệu hóa |
| [WeScan](https://github.com/WeTransferArchive/WeScan) | Scanner camera tùy biến | Swift/SPM/MIT; [tag 3.0.0: iOS 13+](https://github.com/WeTransferArchive/WeScan/blob/3.0.0/Package.swift), khác README cũ ghi iOS 10 | **Đã archive**; [release 3.0.0 · 13/09/2023](https://github.com/WeTransferArchive/WeScan/releases/tag/3.0.0). Tránh thêm mới khi VisionKit đủ |
| [ipp-nio](https://github.com/sliemeobn/ipp-nio) | IPP client cho printer xác định | Swift/SPM, iOS 13+ theo [manifest](https://github.com/sliemeobn/ipp-nio/blob/main/Package.swift); Apache-2.0; kéo NIO/AsyncHTTPClient | [0.1.2 · 13/07/2024](https://github.com/sliemeobn/ipp-nio/releases/tag/v0.1.2); README cảnh báo cần battle-testing/thiếu operations. **Chỉ PoC**, không phải driver đa hãng |
| [OpenPrinting CUPS](https://github.com/OpenPrinting/cups) | Hệ thống/print server, IPP tooling | C; Apache-2.0 kèm exception/NOTICE; không có package iOS được tài liệu hóa | [2.4.20 · 05/10/2026](https://github.com/OpenPrinting/cups/releases/tag/v2.4.20). **Không nhúng nguyên hệ thống vào MVP iOS** |
| [Tesseract](https://github.com/tesseract-ocr/tesseract) | OCR với model/ngôn ngữ riêng | C/C++, Apache-2.0; cần Leptonica/traineddata; chưa xác minh minimum/gói SPM iOS chính thức | [5.5.3 · 24/07/2026](https://github.com/tesseract-ocr/tesseract/releases/tag/5.5.3). Hoãn đến khi benchmark chỉ ra Vision thiếu |
| [OpenCV](https://github.com/opencv/opencv) | Thuật toán xử lý ảnh tùy biến | C/C++, Apache-2.0 ở bản xét; hướng dẫn build iOS có [cảnh báo cũ](https://docs.opencv.org/4.x/d5/da3/tutorial_ios_install.html) | [4.14.0 · 19/07/2026](https://github.com/opencv/opencv/releases/tag/4.14.0). Hoãn; không phải scanner/editor UI |

ZLImageEditor có bản mới hơn [4.0.0 · 19/10/2026](https://github.com/longitachi/ZLImageEditor/releases/tag/4.0.0), nhưng [README cùng tag](https://github.com/longitachi/ZLImageEditor/blob/4.0.0/README.md) ghi iOS 15/Xcode 27, khác [manifest](https://github.com/longitachi/ZLImageEditor/blob/4.0.0/Package.swift) vẫn ghi iOS 10/tools 5.3. Với Xcode 26.4 tại máy, đề xuất bắt đầu PoC ở tag 3.0.0; chưa kết luận bản 4 build được hay không chỉ từ manifest. Xem [README 3.0.0](https://github.com/longitachi/ZLImageEditor/blob/3.0.0/README.md) để kiểm tra phạm vi editor.

Brightroom/StateGraph có thêm dependency build/macro; đây không phải lựa chọn tương đương một cropper nhỏ. Nguồn license: [Brightroom MIT](https://github.com/FluidGroup/Brightroom/blob/5.1.2/LICENSE), [StateGraph Apache-2.0](https://github.com/VergeGroup/swift-state-graph/blob/0.17.0/LICENSE), [manifest StateGraph](https://github.com/VergeGroup/swift-state-graph/blob/0.17.0/Package.swift). Chưa audit toàn bộ dependency graph/tài nguyên bên thứ ba.

Lưu ý `ipp-nio`: ví dụ upstream có cấu hình tắt certificate verification; không sao chép vào production. Chọn giao thức/TLS theo model thực tế. Giữ các notice/license bắt buộc khi phân phối OSS; đánh giá lại phiên bản cụ thể trước khi thêm dependency.

### 6.2. SDK hãng và PDF thương mại

GitHub có thể chỉ chứa **package phân phối binary thương mại**, không đồng nghĩa mã nguồn mở hoặc được dùng miễn phí trong production.

| SDK | Phạm vi và tích hợp được xác minh | Khi nào cân nhắc |
|---|---|---|
| [Brother Print SDK](https://support.brother.com/g/s/es/dev/en/mobilesdk/download/index.html?c=eu_ot&comple=on&lang=en&redirect=on) | 4.13.2; [SDK 4.x: iOS 14+](https://support.brother.com/g/s/es/htmldoc/mobilesdk/overview/supported-environment.html). SDK hãng, tài liệu mô tả nhóm model hỗ trợ; Bluetooth MFi có quy trình PPID. Chưa kiểm tra SPM/EULA trong ZIP | Chỉ khi model mục tiêu nằm trong support list; không suy rộng label/mobile SDK thành mọi Brother A4 |
| [Epson ePOS SDK](https://download4.epson.biz/sec_pubs/pos/reference_en/technology/epson_epos_sdk.html) | 2.37.1 trên [trang tải chính thức](https://www.epson.jp/dl_soft/readme/47014.htm); tập trung máy TM/POS. License giới hạn phần cứng Epson. Chưa kiểm tra minimum OS/binary của bản tải | Chỉ cho model TM hỗ trợ; không hứa Epson EcoTank/A4 nói chung |
| [HP Mobile Print SDK](https://github.com/mobileprint/ios-print-sdk) | AirPrint wrapper, CocoaPods/MIT; [HP công bố deprecated từ 02/2018](https://test.hpopenprint.com/mobile-print/blog/os-printing-advances-allow-deprecation-mobile-print-sdk) | **Tránh**; không bổ sung driver non-AirPrint |
| [Nutrient/PSPDFKit-SP](https://github.com/PSPDFKit/PSPDFKit-SP) | Commercial binary/SPM. [Manifest commit 15/10/2026](https://github.com/PSPDFKit/PSPDFKit-SP/blob/b75c10aa400d12e92a58ed5c7d121bba03dd2fbe/Package.swift) trỏ 27.1.0, iOS 17+, Swift tools 6.4 | Bản đã xét không phù hợp target 15; chỉ xem lại khi thay target/toolchain và cần PDF nâng cao |
| [Apryse](https://github.com/ApryseSDK/pdftron-apple-package) | Commercial binary/SPM; [manifest commit 25/09/2026](https://github.com/ApryseSDK/pdftron-apple-package/blob/afc785e83f94385f96e7a878758b3b0ca4e1f3a0/Package.swift) trỏ 12.2.0-30566. [Guide](https://docs.apryse.com/ios/guides) ghi iOS 11+, nhưng cần kiểm tra binary cụ thể | Khi yêu cầu thật sự cần Office conversion, sửa nội dung PDF, redaction; production cần license |

Điểm không nhất quán đã gặp: README/manifest WeScan khác minimum OS; overview Nutrient cũ hơn manifest cụ thể; ngày phát hành Epson khác giữa khu vực. Khi triển khai, ưu tiên tag/manifest/binary được chọn và release notes, không lấy bài blog cũ làm compatibility contract.

## 7. Quyền truy cập, dữ liệu và giới hạn vận hành

### 7.1. Quyền theo luồng thực sự dùng

| Luồng | Yêu cầu / cách xử lý |
|---|---|
| In/chọn printer qua UIKit | Theo TN3179, high-level printing qua UIKit **không cần quyền Local Network** |
| Tự browse Bonjour | Khai báo `NSLocalNetworkUsageDescription`, `NSBonjourServices` đúng service thực dùng; xử lý denied và lần đầu đang chờ quyền |
| Bonjour service cụ thể | Không mặc định cần multicast entitlement; multicast/broadcast tùy biến hoặc browse mọi service là trường hợp khác |
| Camera scanner | `NSCameraUsageDescription`; kiểm tra camera permission và device support |
| Chọn ảnh bằng PHPicker | Không xin quyền đọc toàn bộ Photos chỉ để chọn ảnh |
| Lưu vào Photos qua PhotoKit | Chọn quyền add-only nếu chỉ thêm ảnh; usage description tương ứng |
| Chọn contact | Picker cấp truy cập tới contact được người dùng chọn; không cần đọc cả contact store |
| File bên ngoài sandbox | Security-scoped access và coordinated I/O theo document picker |

Nguồn: [TN3179 — Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [Photos picker](https://developer.apple.com/documentation/photosui/phpickerviewcontroller), [Photo library](https://developer.apple.com/documentation/photos/phphotolibrary), [Contacts WWDC24](https://developer.apple.com/videos/play/wwdc2024/10121/), [Document access](https://developer.apple.com/documentation/uikit/providing-access-to-directories).

Quyền Local Network khác ATS. Nếu tự gọi HTTP tới printer, đánh giá transport/ATS theo địa chỉ và OS thực tế; không bật `NSAllowsArbitraryLoads` toàn app cho tiện. `NSAllowsLocalNetworking` là cấu hình transport, không cấp quyền privacy và không tự làm certificate hợp lệ. [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)

### 7.2. Dữ liệu và hiệu năng

Các nguyên tắc triển khai đề xuất:

- Giữ file gốc cho đến khi bản chỉnh sửa/PDF xuất ra đã ghi thành công; không xóa scan chỉ vì người dùng đóng share sheet.
- User documents cần lưu bền trong Documents hoặc kho app phù hợp; thumbnail vào Caches, file trung gian vào tmp. Không coi Caches/tmp là bản duy nhất của tài liệu người dùng. [File system directories](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory)
- Downsample ảnh preview bằng Image I/O; xử lý/OCR/render theo từng trang, tránh giữ toàn bộ bitmap trong RAM. Một trang A4 300 dpi khoảng 2480×3508×4 ≈ 34,8 MB chưa kể overhead; 50 trang có thể vượt 1,7 GB nếu cùng giải mã. Đây là phép ước tính RGBA, không phải benchmark app. [Image I/O](https://developer.apple.com/documentation/imageio)
- Preview dùng ảnh nhỏ; bản in cần đủ pixel. Đừng xuất chỉ bằng screenshot màn hình hoặc dùng `UIScreen.scale` làm DPI in. A4 300 dpi là tham chiếu chất lượng, không ép mọi máy in dùng đúng mức đó.
- Giữ vector/text của PDF gốc khi có thể; raster hóa cả file có thể làm giảm độ nét, mất selectable text hoặc khiến file lớn hơn.
- Xử lý thao tác nặng ngoài luồng UI; có progress/cancel và xử lý thiếu dung lượng. Không dùng `Task {}` rồi mặc định cho rằng mọi công việc sẽ tự rời main actor.
- Bản scan/ảnh có thể chứa dữ liệu cá nhân và metadata vị trí. Chỉ gửi ra ngoài theo luồng người dùng chọn; chính sách “xử lý trên thiết bị” phải đúng cả khi thêm analytics/SDK về sau.
- “Local storage” không tự chứng minh đối thủ mã hóa dữ liệu hay hoàn toàn không upload; research này không audit traffic/privacy implementation của ba app.

### 7.3. Chất lượng bản in

Respect `paperRect` và `printableRect`, khác biệt A4/Letter, fit/fill, lề vật lý và duplex. Không dùng KVC để ép property readonly như một API được hỗ trợ. Nhãn/ID cần thử kích thước thật; có máy không hỗ trợ borderless hoặc scale đúng thiết lập mong muốn. [Printable area](https://developer.apple.com/documentation/uikit/uiprintpagerenderer/printablerect)

Cùng Wi-Fi là hướng dẫn người dùng phổ biến nhưng chưa đủ chẩn đoán: guest isolation, multicast bị chặn, VLAN, VPN, printer ngủ hoặc đổi địa chỉ đều cần case xử lý. Với model/triển khai mạng phức tạp, kiểm tra tài liệu AirPrint và kết quả trên mạng thực tế. [AirPrint troubleshooting](https://support.apple.com/en-us/109349)

## 8. Phạm vi triển khai đề xuất và thứ tự xác minh

Đây là đề xuất rút ra từ research, chưa phải tính năng đã code hoặc đã được kiểm thử.

### P0 — Cốt lõi, ưu tiên Apple và iOS 15

1. Nhập PDF/ảnh từ Files và Photos; preview tài liệu trước khi in.
2. Chọn máy in và in bằng UIKit/AirPrint; lưu máy đã chọn khi cần in lại.
3. Scan camera nhiều trang → PDF → lưu/share/print.
4. Xoay/crop ảnh, grayscale/contrast cơ bản; chọn một crop library nếu cần UI sẵn.
5. Xoay/xóa/sắp xếp/ghép/tách trang PDF; markup qua Quick Look.
6. Thư viện local nhỏ: rename/delete/recent; lưu an toàn khi share/in thất bại.

### P1 — Bổ sung khi cần cạnh tranh về xử lý tài liệu

- OCR và tìm text; iOS 16+ native searchable export, iOS 15 có fallback rõ ràng.
- N-up/collage/ID card, printables; calibrate theo máy và khổ giấy thật.
- Web/text/contact-to-PDF; cloud qua Files trước khi tích hợp account từng dịch vụ.
- Custom photo/PDF editing UI chỉ khi Quick Look/native controls thiếu yêu cầu.

### P2 — Chỉ mở sau khi có model và yêu cầu cụ thể

- Custom Bonjour discovery/capability screen.
- Non-AirPrint, Bluetooth/USB, thermal/label printer SDK.
- Network scan từ flatbed/ADF qua eSCL hoặc SDK hãng.
- Office conversion chính xác, true PDF content editing, redaction/chữ ký số.
- Cloud SDK riêng, backend conversion/sync hoặc editor thương mại.

Không thêm backend, SDK in đa hãng, OCR ngoài hoặc custom camera vào baseline nếu chưa có khoảng trống cụ thể mà Apple không đáp ứng.

### Bằng chứng cần có trước khi hứa tương thích

| Nhóm kiểm tra | Case tối thiểu đáng thử | Tiêu chí |
|---|---|---|
| AirPrint | Model color/mono/duplex, có/không online; cùng mạng, guest Wi-Fi | Tìm đúng thiết bị, capability đúng, có đường phục hồi |
| Print layout | PDF nhiều trang, mixed-size, A4/Letter, ảnh portrait/landscape | Preview và bản giấy không mất nội dung/lề |
| Annotation | Highlight/ink/text sau save và print | Hiển thị và xuất đúng; không mất bản gốc |
| Scan | Nhiều trang, nền tối, mép giấy khó thấy, cancel, thiếu quyền | Không mất trang đã lưu; lỗi có thể xử lý |
| OCR | Tiếng Việt/Anh, bảng, mờ, xoay ảnh | Đo độ đúng và kiểm tra search/copy trong PDF xuất |
| Import | iCloud chưa download, provider bên thứ ba, PDF khóa/hỏng | Không báo thành công khi chưa đọc/lưu được |
| Memory/storage | Scan 20–50 trang và ảnh 48 MP, dung lượng thấp | Có giới hạn và progress, không tải mọi bitmap cùng lúc |
| OS/device | iOS 15 baseline, iOS 16 branch, iOS 26 branch; iPhone/iPad | Availability gate và fallback hoạt động |
| Network scanner/SDK hãng | Đúng model, firmware, transport cần bán | In/scan thật; không suy từ tên hãng |

Simulator hữu ích cho UI và một số kiểm thử file, nhưng không thay iPhone/iPad + printer/camera thật. Local network privacy cần kiểm tra trên thiết bị thật theo [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## 9. Những gì báo cáo chưa chứng minh

- Tính năng public của đối thủ có hoạt động đúng, bị paywall thế nào hoặc dùng framework/SDK nào bên trong.
- Tương thích mọi printer của một hãng, Bluetooth/USB, hay scanner MFP.
- Chất lượng OCR tiếng Việt và độ chính xác Office conversion trên dữ liệu sản phẩm.
- Dependency build được với cấu hình hiện tại, minimum trong binary thương mại, EULA/quyền phân phối bản SDK tải về.
- Chất lượng in, scale vật lý, tốc độ, memory peak hoặc xử lý background trên phần cứng.

Research chỉ thêm tài liệu Markdown; không thay mã nguồn, project setting, dependency hoặc cấu hình quyền của app. Các khoảng trống ở trên cần PoC/kiểm thử khi bước sang triển khai.
