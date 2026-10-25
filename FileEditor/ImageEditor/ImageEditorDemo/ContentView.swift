import SwiftUI
import PhotosUI
import ImageEditorKit

struct ContentView: View {
    @State private var image: UIImage?
    @State private var result: UIImage?
    @State private var engine: ImageEditorEngine?
    @State private var picking = false

    var body: some View {
        NavigationView {
            List {
                Section("Ảnh gốc") {
                    Button("Chọn ảnh từ Photos") { picking = true }
                    if let image { preview(image) }
                }
                Section("Sửa bằng") {
                    ForEach(ImageEditorEngine.allCases, id: \.self) { engine in
                        Button(engine.rawValue) { edit(with: engine) }
                            .disabled(image == nil)
                    }
                }
                if let result, let engine {
                    Section("Kết quả · \(engine.rawValue)") {
                        preview(result)
                        Button("Chia sẻ / lưu") {
                            topViewController()?.present(UIActivityViewController(activityItems: [result], applicationActivities: nil), animated: true)
                        }
                    }
                }
            }
            .navigationTitle("Image Editor")
            .sheet(isPresented: $picking) {
                PhotoPicker { image = $0; result = nil }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func preview(_ image: UIImage) -> some View {
        VStack(alignment: .leading) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280)
            Text("\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func edit(with engine: ImageEditorEngine) {
        guard let image, let parent = topViewController() else { return }
        engine.present(image: image, from: parent) { edited in
            guard let edited else { return }
            result = edited
            self.engine = engine
        }
    }
}

func topViewController() -> UIViewController? {
    var top = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}

struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: @MainActor (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: @MainActor (UIImage) -> Void
        init(onPick: @escaping @MainActor (UIImage) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            let onPick = onPick
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in onPick(image) }
            }
        }
    }
}
