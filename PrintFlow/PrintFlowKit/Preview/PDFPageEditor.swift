import PDFKit

/// Thao tác trang PDF. Dùng chung cho PDF editor và màn Print Preview (sửa ở bước in cuối).
@MainActor
public final class PDFPageEditor {
    public init() {}

    public func rotate(_ pdf: PDFDocument, pageAt index: Int, by degrees: Int = 90) {
        guard let page = pdf.page(at: index) else { return }
        page.rotation = (page.rotation + degrees) % 360
    }

    /// Giữ lại ít nhất 1 trang.
    public func delete(_ pdf: PDFDocument, pageAt index: Int) {
        guard pdf.pageCount > 1, index < pdf.pageCount else { return }
        pdf.removePage(at: index)
    }

    public func move(_ pdf: PDFDocument, from source: Int, to destination: Int) {
        guard source != destination, let page = pdf.page(at: source), destination < pdf.pageCount else { return }
        pdf.removePage(at: source)
        pdf.insert(page, at: destination)
    }

    /// `order[i]` = index cũ của trang sẽ nằm ở vị trí i.
    public func reorder(_ pdf: PDFDocument, to order: [Int]) {
        let pages = order.compactMap(pdf.page(at:))
        guard pages.count == pdf.pageCount else { return }
        // Đưa lần lượt từng trang về vị trí i; các trang chưa xếp luôn nằm ở chỉ số >= i.
        for (i, page) in pages.enumerated() {
            move(pdf, from: pdf.index(for: page), to: i)
        }
    }

    // TODO: n-up (2/4 trang trên 1 tờ), thêm watermark, chèn trang trắng.
}
