import SwiftUI
import PDFKit
import PDFEditorKit

struct ContentView: View {
    struct Output: Identifiable {
        let id = UUID()
        let label: String
        let url: URL
        let pages: Int
    }

    @State private var source: URL?
    @State private var outputs: [Output] = []
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            List {
                Section("PDF gốc") {
                    Button("Chọn PDF từ Files") { importing = true }
                    Button("Tạo PDF mẫu (4 trang)") { source = makeSamplePDF() }
                    if let source {
                        NavigationLink(source.lastPathComponent) { PDFPreview(url: source) }
                    }
                }
                Section("Sửa bằng") {
                    ForEach(PDFEditorEngine.allCases, id: \.self) { engine in
                        Button(engine.isAvailable ? engine.rawValue : "\(engine.rawValue) — cần iOS mới hơn") {
                            open(engine.rawValue, engine.makeViewController(url:onSave:))
                        }
                        .disabled(source == nil || !engine.isAvailable)
                    }
                }
                Section("Thao tác trang (PDFKit)") {
                    ForEach(PDFPageTool.allCases, id: \.self) { tool in
                        Button(tool.rawValue) { open(tool.rawValue, tool.makeViewController(url:onSave:)) }
                            .disabled(source == nil)
                    }
                }
                if !outputs.isEmpty {
                    Section("Kết quả") {
                        ForEach(outputs.reversed()) { output in
                            NavigationLink("\(output.label) • \(output.pages) trang") { PDFPreview(url: output.url) }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundColor(.red)
                }
            }
            .navigationTitle("PDF Editor")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                error = nil
                do { source = try copyIn(try result.get()) } catch { self.error = error.localizedDescription }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func open(_ label: String, _ make: (URL, @escaping @MainActor (URL) -> Void) -> UIViewController?) {
        guard let source else { return }
        guard let editor = make(source, { url in
            outputs.append(Output(label: label, url: url, pages: PDFDocument(url: url)?.pageCount ?? 0))
        }) else {
            error = "Không mở được PDF (hỏng, bị khóa hoặc cấm sửa trang)."
            return
        }
        error = nil
        topViewController()?.present(editor, animated: true)
    }

    /// File từ Files là security-scoped; copy vào sandbox để editor đọc thoải mái.
    private func copyIn(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    private func makeSamplePDF() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample.pdf")
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        try? UIGraphicsPDFRenderer(bounds: a4).writePDF(to: url) { context in
            for number in 1...4 {
                context.beginPage()
                // Số trang to để nhận ra trong thumbnail khi thử Reorder/Split/Merge.
                ("\(number)" as NSString).draw(at: CGPoint(x: 48, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 160)])
                let text = "Trang \(number)\n\nĐây là PDF mẫu để thử highlight, thêm chữ, vẽ tay, chèn hình và thao tác trang. " +
                    String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 12)
                (text as NSString).draw(in: a4.insetBy(dx: 48, dy: 60).offsetBy(dx: 0, dy: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        }
        return url
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
