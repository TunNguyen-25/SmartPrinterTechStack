# Research: tính năng Scan Document trên iOS

Ngày: **25/10/2026** · SDK kiểm tra: **iPhoneOS 26.4** (Xcode trên máy) · Deployment target của app: **iOS 15.0**.
Bổ sung cho mục 4.2–4.3 của [smart-printer-ios-research.md](smart-printer-ios-research.md). POC: [DocumentScanner/](../DocumentScanner/).

## 1. Kết luận

**Dùng framework Apple, không cần thư viện ngoài.** VisionKit + Vision + Core Image + PDFKit đủ để làm luồng scan → làm sạch ảnh → OCR → PDF tìm kiếm được, chạy hoàn toàn on-device, miễn phí. Chỉ cân nhắc SDK thương mại khi cần UI scanner tùy biến hoàn toàn hoặc trích xuất chuyên biệt (CCCD, MRZ, IBAN…) mà Vision không làm sẵn.

## 2. Scan được tới mức nào (theo iOS)

| Mức | API | iOS | Làm được gì |
|---|---|---|---|
| 1. Scanner có sẵn UI | VisionKit `VNDocumentCameraViewController` | 13+ | Nhận mép giấy, **auto-capture**, chụp nhiều trang, crop/nắn phối cảnh, chỉnh mép thủ công, filter màu/xám/đen trắng/ảnh, sắp xếp/xóa trang trong màn review. Trả về ảnh từng trang + `title`. |
| 2. Pipeline tự làm | Vision `VNDetectDocumentSegmentationRequest` / `VNDetectRectanglesRequest` + Core Image `CIPerspectiveCorrection` | 15+ / 11+ | Tự tìm mép giấy trên ảnh bất kỳ (ảnh Photos, ảnh chụp custom camera) và nắn phẳng. Dùng khi nhập ảnh có sẵn hoặc cần UI camera riêng. |
| 3. Làm sạch ảnh | Core Image `CIDocumentEnhancer`, `CIColorControls`, `CIColorThreshold` | 14+ | Bỏ bóng, làm trắng nền, tăng tương phản; xám; đen trắng. |
| 4. OCR text | Vision `VNRecognizeTextRequest` (`.accurate`) | 13+ (tiếng Việt `vi-VT` có trên OS mới) | Lấy text + bounding box từng dòng. Gọi `supportedRecognitionLanguages()` để biết máy hỗ trợ gì. |
| 5. PDF tìm kiếm được | PDFKit `PDFDocumentWriteOption.saveTextFromOCROption` | 16+ | PDFKit tự OCR và nhúng lớp text ẩn → search/copy được trong mọi app đọc PDF. `saveImagesAsJPEGOption` (16.4+) giảm dung lượng. |
| 6. Live text / QR | VisionKit `DataScannerViewController` | 16+, chip A12+ | Highlight text/barcode trực tiếp trên camera, chạm để lấy; lọc theo `textContentType` (URL, phone, email, ngày, số tiền, tracking…); `capturePhoto()`. Không phải scanner nhiều trang. |
| 7. Hiểu cấu trúc tài liệu | Vision `RecognizeDocumentsRequest` | **26+** | Tiêu đề, đoạn văn, **bảng (dòng × cột, ô gộp)**, **list (loại bullet/đánh số)**, barcode trong trang, **data detector** (phone, email, link, địa chỉ, ngày, số tiền, vận đơn, chuyến bay…). |
| 8. Kiểm tra chất lượng ảnh | Vision `DetectLensSmudgeRequest` | **26+** | Điểm 0–1 khả năng ống kính bẩn → nhắc lau camera rồi chụp lại. |

Giới hạn cần biết:

- **Không điều khiển scanner phần cứng (flatbed/ADF)** qua ImageCaptureCore trên iOS — `ICScannerDevice` là `IC_UNAVAILABLE(ios)`. Muốn scan từ máy in đa năng phải làm eSCL/SDK hãng (ngoài phạm vi này).
- `VNDocumentCameraViewController` **không tùy biến UI** được (màu, nút, overlay) và không cấu hình filter mặc định.
- OCR plain text **không giữ bố cục**; iOS 26 có cấu trúc bảng/list nhưng vẫn không phải converter PDF→Word.
- Scan nhiều trang giữ hết ảnh trong RAM nếu làm ngây thơ — trang A4 300 dpi ≈ 35 MB bitmap; 30+ trang nên ghi đĩa từng trang.

## 3. Tính năng hay có thể làm (đều native)

| Tính năng | Cách làm |
|---|---|
| Auto-capture nhiều trang, chỉnh mép | Có sẵn trong VisionKit document camera |
| Import ảnh có sẵn → tự cắt mép | Vision segmentation + perspective correction (POC đã làm) |
| Filter Enhance / Xám / Đen trắng | Core Image (POC đã làm) |
| PDF tìm kiếm & copy được | PDFKit OCR option iOS 16+ (POC đã làm) |
| Tự đặt tên file từ tiêu đề | `RecognizeDocumentsRequest` → `document.title` (iOS 26), fallback dòng OCR đầu tiên |
| Trích bảng → CSV/Excel | `document.tables` → `rows` → `cell.content.text.transcript` (iOS 26) |
| Tách thông tin hóa đơn / danh thiếp | `detectedData`: số tiền, phone, email, địa chỉ, ngày (iOS 26). iOS 15–25: `NSDataDetector` trên text OCR |
| Đọc QR/barcode trong tài liệu | `document.barcodes` (iOS 26) hoặc `VNDetectBarcodesRequest` |
| Cảnh báo camera bẩn | `DetectLensSmudgeRequest` (iOS 26) |
| Live text / quét QR nhanh | `DataScannerViewController` (iOS 16+) |
| Scan → in ngay | Ghép với `UIPrintInteractionController` đã có trong app |

## 4. Tech stack đề xuất

```
VisionKit  VNDocumentCameraViewController   (scan camera, iOS 13+)
Vision     VNDetectDocumentSegmentationRequest + VNDetectRectanglesRequest  (import ảnh)
Core Image CIPerspectiveCorrection, CIDocumentEnhancer, CIColorControls, CIColorThreshold
Vision     VNRecognizeTextRequest            (OCR, mọi OS)
           RecognizeDocumentsRequest         (cấu trúc, #available(iOS 26))
           DetectLensSmudgeRequest           (chất lượng, #available(iOS 26))
PDFKit     PDFPage(image:options:) + saveTextFromOCROption  (PDF searchable, #available(iOS 16))
VisionKit  DataScannerViewController         (tùy chọn: live text/QR, #available(iOS 16))
```

Quyền: `NSCameraUsageDescription`. Ảnh từ Photos dùng `PHPickerViewController` → không cần quyền thư viện ảnh.

Bẫy kỹ thuật gặp khi làm POC:

- **Không `import DataDetection` trực tiếp** khi target iOS 15: framework chỉ có từ iOS 26, link cứng sẽ lỗi khi chạy trên OS cũ. Dùng type qua Vision (`match.details`) là đủ.
- `VNDetectDocumentSegmentationRequest` trên **simulator** trả về cả khung với `confidence = 0` (model ML không chạy) → phải check confidence và fallback `VNDetectRectanglesRequest`. Trên máy thật cần đo lại.
- `DetectLensSmudgeRequest` lỗi `internalError` trên simulator — chỉ test được trên máy thật.
- `VNDocumentCameraViewController.delegate` là weak → giữ delegate sống tới khi camera đóng.

## 5. Thư viện bên thứ ba

| Thư viện | Tình trạng | Khi nào dùng |
|---|---|---|
| [WeScan](https://github.com/WeTransferArchive/WeScan) | MIT, **đã archive** (3.0.0, 2023) | Không thêm mới; VisionKit thay được |
| [Genius Scan SDK](https://geniusscansdk.com/vs/visionkit) | Thương mại; [SDK 6 ra 05/2026](https://blog.thegrizzlylabs.com/2026/05/announcing-genius-scan-sdk-6.html). Detection, enhance, PDF, OCR, trích receipt/danh thiếp/IBAN, cross-platform | Khi cần UI tùy biến + extraction chuyên biệt + cùng SDK cho Android. Đánh giá "best in class" là của vendor |
| [Scanbot SDK](https://scanbot.io/blog/ios-document-scanners-wescan-vs-visionkit/) | Thương mại; **đã được Apryse mua lại** — kiểm tra lại roadmap/giá | Tương tự Genius Scan; mạnh về MRZ/CCCD/barcode |
| Google ML Kit Document Scanner | **Chỉ Android**; iOS không có bản chính thức (wrapper Flutter/RN dùng VisionKit ở iOS) | Không áp dụng |
| Tesseract / OpenCV | Apache-2.0, C/C++ | Chỉ khi benchmark cho thấy Vision thiếu |

Ghi chú: bài của Scanbot nói VisionKit có lỗi UI trên iOS/iPadOS 26 — đây là nhận định của đối thủ cạnh tranh, chưa kiểm chứng; cần thử trên máy thật.

## 6. POC `DocumentScanner`

Mở `SmartPrintTechStack.xcworkspace` → scheme **DocumentScannerDemo**.

```
DocumentScanner/
├── DocumentScannerKit/            framework, không dependency ngoài
│   ├── ScanEngine.swift            VisionKit Document Camera | DataScanner
│   ├── LiveScannerViewController   DataScanner: live text/QR, chạm để copy, chụp trang
│   └── DocumentProcessor.swift     autoCrop · ScanFilter · OCR · cấu trúc (26) · smudge (26) · makePDF
└── DocumentScannerDemo/            app SwiftUI để test
    ├── ContentView.swift           scan / nhập ảnh / filter / xóa-sắp xếp trang / phân tích / xuất PDF
    ├── SampleDocument.swift        "ảnh chụp" giả: hóa đơn tiếng Việt nghiêng trên nền tối
    └── SelfTest.swift              chạy cả pipeline, in kết quả, exit 0/1
```

Self-check không cần camera:

```sh
xcrun simctl launch --console-pty booted tuandev.DocumentScannerDemo -selftest
```

Kết quả đo trên simulator iPhone 17 Pro, iOS 26.4 (ảnh mẫu tổng hợp, chưa phải giấy thật):

| Bước | Kết quả |
|---|---|
| Auto-crop | 1500×2000 → 1054×1487 (giấy gốc 1050×1485), qua fallback rectangle |
| OCR tiếng Việt | Đọc đúng gần hết; lỗi dấu nhỏ: "để đổi trả" → "đề đồi trả", "Đóng" → "Động" |
| RecognizeDocuments | Đúng tiêu đề, **bảng 4×3 đúng ô**, list 3 mục, nhận 3 số tiền VND, phone, email, link, ngày |
| Lens smudge | Lỗi trên simulator |
| PDF searchable | 2 trang, 428 KB, text layer 885 ký tự, tìm được "HÓA ĐƠN" |

Cần test trên máy thật: document camera, DataScanner, smudge, segmentation ML, tài liệu thật (giấy nhăn, bóng, chữ nhỏ, chữ viết tay), scan 20–50 trang (RAM/thời gian), máy iOS 15/16.

## Nguồn

- [VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) · [DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller)
- [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) · [WWDC25 – Read documents using the Vision framework](https://developer.apple.com/videos/play/wwdc2025/272/) · [WWDC Notes tóm tắt](https://wwdcnotes.com/documentation/wwdc25-272-read-documents-using-the-vision-framework/)
- [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) · [saveTextFromOCROption](https://developer.apple.com/documentation/pdfkit/pdfdocumentwriteoption/savetextfromocroption)
- [Google ML Kit release notes](https://developers.google.com/ml-kit/release-notes) (document scanner chỉ có artifact Android)
- Header/swiftinterface trong `iPhoneOS26.4.sdk`: `Vision`, `VisionKit`, `PDFKit/PDFDocument.h`, `PDFKit/PDFPage.h`, `CoreImage/CIFilterBuiltins.h`
