import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import LANShareKit

final class TransferModel: ObservableObject {
    struct Incoming: Identifiable {
        let id: UUID
        let name: String
        var received: Int64
        var total: Int64?
    }

    @Published private(set) var url: URL?
    @Published private(set) var incoming: [Incoming] = []
    @Published private(set) var files: [URL] = []
    @Published private(set) var error: String?

    private var server: LANShareServer?
    private var task: Task<Void, Never>?

    static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LANShare")

    func start() {
        reloadFiles()
        guard server == nil else { return }
        let server = LANShareServer(directory: Self.directory) { [weak self] event in
            // main queue (not Task) keeps events in order, so a late .progress can't resurrect a finished row
            DispatchQueue.main.async { self?.handle(event) }
        }
        self.server = server
        url = server.shareURL()
        error = url == nil ? "Hãy kết nối Wi-Fi (hoặc bật Personal Hotspot)" : nil
        task = Task { [weak self] in
            do { try await server.run() } catch {
                self?.error = "Server lỗi: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        guard let server else { return }
        self.server = nil
        task = nil
        url = nil
        incoming = []
        Task { await server.stop() }
    }

    private func handle(_ event: LANShareServer.Event) {
        switch event {
        case let .progress(id, name, received, total):
            if let i = incoming.firstIndex(where: { $0.id == id }) {
                incoming[i].received = received
            } else {
                incoming.append(Incoming(id: id, name: name, received: received, total: total))
            }
        case let .completed(id, _):
            incoming.removeAll { $0.id == id }
            reloadFiles()
        case let .failed(id, _):
            incoming.removeAll { $0.id == id }
        }
    }

    private func reloadFiles() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        files = urls.sorted { $0.modificationDate > $1.modificationDate }
    }
}

struct TransferView: View {
    @StateObject private var model = TransferModel()
    @State private var previewURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            List {
                addressSection

                if !model.incoming.isEmpty {
                    Section("Đang nhận") {
                        ForEach(model.incoming) { IncomingRow(item: $0) }
                    }
                }

                Section("Đã nhận") {
                    if model.files.isEmpty {
                        Text("Chưa có file").foregroundStyle(.secondary)
                    }
                    ForEach(model.files, id: \.self) { file in
                        Button { previewURL = file } label: { FileRow(url: file) }
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("LAN Share")
            .animation(.default, value: model.incoming.map(\.id))
        }
        .navigationViewStyle(.stack)
        // `in:` lets the user swipe between all received files inside QuickLook
        .quickLookPreview($previewURL, in: model.files)
        // iOS suspends the app in background, which kills the server: run only while visible.
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.start() }
            if phase == .background { model.stop() }
        }
        .onAppear {
            model.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var addressSection: some View {
        Section {
            VStack(spacing: 12) {
                if let url = model.url, let qr = QRCode.image(for: url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .accessibilityLabel("QR code của địa chỉ chia sẻ")
                    Text(url.absoluteString)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        } footer: {
            Text("Mở địa chỉ trên bằng trình duyệt của máy tính cùng mạng Wi-Fi. Giữ màn hình này mở khi đang truyền file.")
        }
    }
}

private struct IncomingRow: View {
    let item: TransferModel.Incoming

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name).lineLimit(1).truncationMode(.middle)
            if let total = item.total, total > 0 {
                ProgressView(value: Double(item.received), total: Double(total))
                Text("\(item.received.byteText) / \(total.byteText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text(item.received.byteText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct FileRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: url.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(url.fileSize.byteText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Mở xem trước")
    }
}

private extension URL {
    var modificationDate: Date {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    var fileSize: Int64 {
        Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    var symbolName: String {
        guard let type = UTType(filenameExtension: pathExtension) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}

private extension Int64 {
    var byteText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
