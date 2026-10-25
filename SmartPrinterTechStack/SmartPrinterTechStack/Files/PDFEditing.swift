import PDFKit

nonisolated func makeEditedPDF(source: URL, pageIndices: [Int], rotations: [Int: Int]) throws -> URL {
    try PDFEditing.write(source: source, pageIndices: pageIndices, rotations: rotations)
}

nonisolated enum PDFEditing {
    enum Failure: Error, LocalizedError {
        case corrupt, protected, invalidPages, invalidCrop
        var errorDescription: String? {
            switch self {
            case .corrupt: "Không đọc được PDF hợp lệ."
            case .protected: "PDF khóa hoặc hạn chế quyền. Hãy dùng bản đã được chủ sở hữu cho phép mở khóa bên ngoài app."
            case .invalidPages: "Cần ít nhất một trang; chỉ số trang phải hợp lệ, không trùng và góc xoay phải là bội số 90°."
            case .invalidCrop: "Crop box phải có kích thước dương và nằm trong media box (tọa độ PDF trước xoay). Crop không xóa nội dung ẩn."
            }
        }
    }
    static func open(_ source: URL) throws -> PDFDocument {
        try Task.checkCancellation()
        guard let pdf = PDFDocument(url: source) else { throw Failure.corrupt }
        guard !pdf.isLocked, !pdf.isEncrypted, pdf.allowsDocumentChanges, pdf.allowsDocumentAssembly,
              pdf.allowsCommenting, pdf.allowsPrinting else { throw Failure.protected }
        guard pdf.pageCount > 0 else { throw Failure.corrupt }
        return pdf
    }

    static func write(source: URL, pageIndices: [Int], rotations: [Int: Int] = [:], crops: [Int: CGRect] = [:], appending: [URL] = []) throws -> URL {
        let original = try open(source)
        let selected = Set(pageIndices)
        guard !pageIndices.isEmpty, selected.count == pageIndices.count,
              pageIndices.allSatisfy({ (0..<original.pageCount).contains($0) }),
              rotations.allSatisfy({ selected.contains($0.key) && $0.value % 90 == 0 }),
              crops.keys.allSatisfy({ selected.contains($0) }) else { throw Failure.invalidPages }
        let result = PDFDocument()
        // Retain source documents while PDFKit serializes their vector pages and annotations.
        var inputs = [original]
        for index in pageIndices {
            try Task.checkCancellation()
            guard let page = original.page(at: index)?.copy() as? PDFPage else { throw Failure.corrupt }
            if let crop = crops[index] {
                guard crop.origin.x.isFinite, crop.origin.y.isFinite, crop.width.isFinite, crop.height.isFinite,
                      crop.width > 0, crop.height > 0, page.bounds(for: .mediaBox).contains(crop) else { throw Failure.invalidCrop }
                page.setBounds(crop, for: .cropBox)
            }
            let delta = (rotations[index] ?? 0) % 360
            page.rotation = ((page.rotation + delta) % 360 + 360) % 360
            result.insert(page, at: result.pageCount)
        }
        for url in appending {
            let pdf = try open(url)
            inputs.append(pdf)
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index)?.copy() as? PDFPage else { throw Failure.corrupt }
                result.insert(page, at: result.pageCount)
            }
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("edited-\(UUID()).pdf")
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: output) } }
        try Task.checkCancellation()
        guard withExtendedLifetime(inputs, { result.write(to: output) }),
              let reopened = PDFDocument(url: output), reopened.pageCount == result.pageCount else { throw CocoaError(.fileWriteUnknown) }
        try Task.checkCancellation()
        complete = true
        return output
    }

    @concurrent static func export(source: URL, pageIndices: [Int], rotations: [Int: Int], crops: [Int: CGRect], appending: [URL]) async throws -> URL {
        try write(source: source, pageIndices: pageIndices, rotations: rotations, crops: crops, appending: appending)
    }
    @concurrent static func load(source: URL) async throws -> sending PDFDocument { try open(source) }
    @concurrent static func thumbnail(source: URL, index: Int, rotation: Int, crop: CGRect?) async throws -> UIImage {
        let pdf = try open(source)
        guard let page = pdf.page(at: index) else { throw Failure.invalidPages }
        page.rotation += rotation
        if let crop { page.setBounds(crop, for: .cropBox) }
        try Task.checkCancellation()
        return page.thumbnail(of: CGSize(width: 80, height: 100), for: .cropBox)
    }
}
