import UIKit

/// Ảnh "chụp" giả: tờ giấy nghiêng trên nền tối, có tiêu đề, đoạn văn tiếng Việt, bảng, list, phone/email/link.
/// Dùng để thử auto-crop, OCR, cấu trúc và PDF trên simulator (không có camera).
enum SampleDocument {
    static func make() -> UIImage {
        let canvas = CGSize(width: 1500, height: 2000)
        let paper = CGRect(x: 0, y: 0, width: 1050, height: 1485) // tỉ lệ A4
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor(white: 0.18, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))

            let cg = context.cgContext
            cg.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            cg.rotate(by: -0.12)
            cg.translateBy(x: -paper.width / 2, y: -paper.height / 2)
            UIColor(white: 0.97, alpha: 1).setFill()
            cg.fill(paper)

            func draw(_ text: String, _ y: CGFloat, size: CGFloat, bold: Bool = false, x: CGFloat = 70) {
                let font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                (text as NSString).draw(in: CGRect(x: x, y: y, width: paper.width - x - 70, height: 400),
                                        withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }

            draw("HÓA ĐƠN DỊCH VỤ IN ẤN", 70, size: 48, bold: true)
            draw("Cảm ơn quý khách đã sử dụng dịch vụ. Vui lòng kiểm tra kỹ thông tin bên dưới trước khi thanh toán.", 160, size: 26)

            // Bảng 3 cột × 4 dòng
            let columns: [CGFloat] = [70, 520, 750, 980]
            let rows = [["Mặt hàng", "Số lượng", "Thành tiền"],
                        ["In tài liệu A4", "120", "240.000 đ"],
                        ["Scan sang PDF", "35", "70.000 đ"],
                        ["Đóng gáy", "2", "30.000 đ"]]
            let tableTop: CGFloat = 300, rowHeight: CGFloat = 70
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2)
            for row in 0...rows.count {
                cg.move(to: CGPoint(x: columns[0], y: tableTop + CGFloat(row) * rowHeight))
                cg.addLine(to: CGPoint(x: columns[3], y: tableTop + CGFloat(row) * rowHeight))
            }
            for x in columns {
                cg.move(to: CGPoint(x: x, y: tableTop))
                cg.addLine(to: CGPoint(x: x, y: tableTop + CGFloat(rows.count) * rowHeight))
            }
            cg.strokePath()
            for (r, row) in rows.enumerated() {
                for (c, cell) in row.enumerated() {
                    draw(cell, tableTop + CGFloat(r) * rowHeight + 18, size: 26, bold: r == 0, x: columns[c] + 16)
                }
            }

            draw("Ghi chú:", 640, size: 30, bold: true)
            draw("1. Nhận hàng trong vòng 2 ngày.", 690, size: 26)
            draw("2. Giữ hóa đơn để đổi trả.", 735, size: 26)
            draw("3. Thanh toán bằng tiền mặt hoặc chuyển khoản.", 780, size: 26)

            draw("Liên hệ: 0912 345 678 · hotro@example.com", 880, size: 26)
            draw("Website: https://example.com/in-an", 925, size: 26)
            draw("Ngày lập: 25/10/2026", 970, size: 26)
        }
    }
}
