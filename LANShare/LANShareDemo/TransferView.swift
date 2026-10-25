import SwiftUI
import LANShareKit

final class TransferModel: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var received: [String] = []
    @Published private(set) var error: String?

    private var server: LANShareServer?
    private var task: Task<Void, Never>?

    static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LANShare")

    func start() {
        guard server == nil else { return }
        let server = LANShareServer(directory: Self.directory) { [weak self] saved in
            Task { @MainActor in self?.received.insert(saved.lastPathComponent, at: 0) }
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
        Task { await server.stop() }
    }
}

struct TransferView: View {
    @StateObject private var model = TransferModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            List {
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

                Section("Đã nhận") {
                    if model.received.isEmpty {
                        Text("Chưa có file").foregroundStyle(.secondary)
                    }
                    ForEach(model.received, id: \.self) { Text($0) }
                }
            }
            .navigationTitle("LAN Share")
        }
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
}
