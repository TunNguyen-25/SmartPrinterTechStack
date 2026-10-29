import CoreGraphics

/// Cấu hình in, chỉnh ở màn Print Preview. Số bản và khoảng trang để hộp thoại AirPrint lo.
public struct PrintSettings: Sendable, Equatable {
    public enum Paper: Sendable, CaseIterable {
        case a4, letter

        /// Điểm PDF (1/72 inch), chiều dọc.
        public var size: CGSize {
            switch self {
            case .a4: CGSize(width: 595, height: 842)
            case .letter: CGSize(width: 612, height: 792)
            }
        }
    }

    public var paper: Paper = .a4
    public var isLandscape = false
    public var grayscale = false

    public init() {}

    public var pageSize: CGSize {
        isLandscape ? CGSize(width: paper.size.height, height: paper.size.width) : paper.size
    }
}
