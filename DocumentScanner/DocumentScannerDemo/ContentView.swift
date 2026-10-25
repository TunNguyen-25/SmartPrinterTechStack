import SwiftUI
import PhotosUI
import PDFKit
import DocumentScannerKit

struct ContentView: View {
    @State private var pages: [UIImage] = []
    @State private var filter: ScanFilter = .original
    @State private var filtered: [UIImage] = []
    @State private var picking = false
    @State private var busy: String?
    @State private var report: (title: String, text: String)?
    @State private var pdf: URL?

    private var isIOS26: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(ScanEngine.allCases, id: \.self) { engine in
                        Button(engine.isAvailable ? engine.rawValue : "\(engine.rawValue) — máy/OS không hỗ trợ") { scan(with: engine) }
                            .disabled(!engine.isAvailable)
                    }
                } header: { Text("Scan bằng camera") } footer: { Text("Cần máy thật; simulator dùng phần nhập ảnh bên dưới.") }

                Section {
                    Button("Chọn ảnh từ Photos") { picking = true }
                    Button("Ảnh mẫu: giấy nghiêng trên nền tối") { autoCrop([SampleDocument.make()]) }
                } header: { Text("Nhập ảnh · auto-crop bằng Vision") } footer: {
                    Text("VNDetectDocumentSegmentationRequest (fallback VNDetectRectanglesRequest) + CIPerspectiveCorrection. Không thấy mép giấy thì giữ ảnh gốc.")
                }

                if !pages.isEmpty {
                    Section("Trang (\(pages.count)) · vuốt để xóa, Edit để đổi thứ tự") {
                        Picker("Bộ lọc", selection: $filter) {
                            ForEach(ScanFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        ForEach(Array(filtered.enumerated()), id: \.offset) { index, image in
                            HStack {
                                Image(uiImage: image).resizable().scaledToFit().frame(height: 120)
                                Text("Trang \(index + 1)\n\(Int(image.size.width * image.scale))×\(Int(image.size.height * image.scale)) px")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .onDelete { pages.remove(atOffsets: $0); refilter() }
                        .onMove { pages.move(fromOffsets: $0, toOffset: $1); refilter() }
                    }

                    Section("Phân tích (Vision, on-device)") {
                        Button("OCR text — VNRecognizeTextRequest") { analyze("OCR") { try DocumentProcessor.recognizeText(in: $0) } }
                        Button(isIOS26 ? "Cấu trúc bảng/list/data — RecognizeDocumentsRequest" : "Cấu trúc — cần iOS 26") {
                            guard #available(iOS 26.0, *) else { return }
                            analyze("Cấu trúc") { try await DocumentProcessor.analyzeStructure(of: $0) }
                        }
                        .disabled(!isIOS26)
                        Button(isIOS26 ? "Kiểm tra ống kính bẩn — DetectLensSmudgeRequest" : "Ống kính bẩn — cần iOS 26") {
                            guard #available(iOS 26.0, *) else { return }
                            analyze("Ống kính bẩn") { String(format: "confidence %.2f (cao = nhiều khả năng bẩn)", try await DocumentProcessor.smudgeConfidence(of: $0)) }
                        }
                        .disabled(!isIOS26)
                        Button("Ngôn ngữ OCR máy này hỗ trợ") {
                            report = ("Ngôn ngữ OCR", DocumentProcessor.supportedOCRLanguages().joined(separator: ", "))
                        }
                    }

                    Section("Xuất PDF") {
                        Button("Tạo PDF (searchable nếu iOS 16+)") { exportPDF() }
                        if let pdf {
                            NavigationLink("Xem \(pdf.lastPathComponent) · \(fileSize(pdf))") { PDFPreview(url: pdf) }
                            Button("Chia sẻ / in / lưu Files") {
                                topViewController()?.present(UIActivityViewController(activityItems: [pdf], applicationActivities: nil), animated: true)
                            }
                        }
                    }
                }

                if let report {
                    Section(report.title) {
                        Text(report.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Doc Scanner")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { if !pages.isEmpty { Button("Xóa hết") { pages = []; refilter() } } }
                ToolbarItem(placement: .navigationBarTrailing) { if !pages.isEmpty { EditButton() } }
            }
            .overlay { if let busy { ProgressView(busy).padding().background(.regularMaterial).cornerRadius(12) } }
            .sheet(isPresented: $picking) { PhotoPicker { autoCrop($0) } }
            .onChange(of: filter) { _ in refilter() }
        }
        .navigationViewStyle(.stack)
    }

    private func scan(with engine: ScanEngine) {
        guard let parent = topViewController() else { return }
        engine.present(from: parent) { scanned in
            pages += scanned
            refilter()
        }
    }

    private func autoCrop(_ images: [UIImage]) {
        run("Đang tìm mép giấy…") {
            images.map { DocumentProcessor.autoCrop($0) ?? $0 }
        } done: { pages += $0; refilter() }
    }

    private func refilter() {
        pdf = nil
        let pages = pages, filter = filter
        run("Đang áp bộ lọc…") { pages.map(filter.apply) } done: { filtered = $0 }
    }

    private func analyze(_ title: String, _ work: @escaping @Sendable (UIImage) async throws -> String) {
        let pages = filtered
        run("Đang phân tích…") {
            var parts: [String] = []
            for (index, page) in pages.enumerated() {
                let start = Date()
                let result = (try? await work(page)) ?? "(lỗi)"
                parts.append("── Trang \(index + 1) · \(String(format: "%.2f", Date().timeIntervalSince(start)))s ──\n\(result)")
            }
            return parts.joined(separator: "\n\n")
        } done: { report = (title, $0) }
    }

    private func exportPDF() {
        let pages = filtered
        run("Đang tạo PDF (OCR mọi trang)…") {
            DocumentProcessor.makePDF(pages: pages, searchable: true)
        } done: { pdf = $0 }
    }

    /// Chạy việc nặng ngoài main thread, hiện spinner.
    private func run<T: Sendable>(_ label: String, _ work: @escaping @Sendable () async -> T, done: @escaping (T) -> Void) {
        busy = label
        Task {
            let result = await Task.detached { await work() }.value
            done(result)
            busy = nil
        }
    }

    private func fileSize(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

func topViewController() -> UIViewController? {
    var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}

struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: @MainActor ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: @MainActor ([UIImage]) -> Void
        init(onPick: @escaping @MainActor ([UIImage]) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let onPick = onPick
            Task {
                var images: [UIImage] = []
                for result in results {
                    if let image = await Self.load(result.itemProvider) { images.append(image) }
                }
                if !images.isEmpty { onPick(images) }
            }
        }

        private static func load(_ provider: NSItemProvider) async -> UIImage? {
            guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
            return await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in continuation.resume(returning: object as? UIImage) }
            }
        }
    }
}
