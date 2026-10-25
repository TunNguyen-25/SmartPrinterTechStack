import UIKit
import PDFKit
import PaperKit
import PencilKit

/// Stack P3: canvas PaperKit (vẽ, hình, text box, ảnh) phủ lên ảnh render của từng trang.
/// Khi lưu, markup được vẽ đè (flatten) lên nội dung vector của trang gốc → không còn sửa lại được ở app khác.
@available(iOS 26.0, *)
final class PaperKitPDFViewController: UIViewController {
    private let document: PDFDocument
    private let onSave: @MainActor (URL) -> Void
    private let toolPicker = PKToolPicker()
    private var markups: [Int: PaperMarkup] = [:]
    private var pageIndex = 0
    private var paper: PaperMarkupViewController?
    private var previousItem: UIBarButtonItem!
    private var nextItem: UIBarButtonItem!

    init(document: PDFDocument, onSave: @escaping @MainActor (URL) -> Void) {
        self.document = document
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Kích thước trang sau khi xoay — cũng là hệ tọa độ (gốc trên-trái) của markup.
    private static func pageRect(_ page: PDFPage) -> CGRect {
        let size = page.bounds(for: .cropBox).size
        return CGRect(origin: .zero, size: page.rotation % 180 == 0 ? size : CGSize(width: size.height, height: size.width))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        previousItem = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(previousPage))
        nextItem = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: self, action: #selector(nextPage))
        navigationItem.leftBarButtonItems = [UIBarButtonItem(title: "Hủy", style: .plain, target: self, action: #selector(cancel)), previousItem, nextItem]
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Lưu", style: .done, target: self, action: #selector(save))
        // Nút "+" trong tool picker mở menu chèn hình / text box / ảnh của PaperKit.
        toolPicker.accessoryItem = UIBarButtonItem(image: UIImage(systemName: "plus.circle"), primaryAction: UIAction { [weak self] _ in self?.showInsertMenu() })
        showPage(0)
    }

    private func showPage(_ index: Int) {
        if let paper {
            markups[pageIndex] = paper.markup
            toolPicker.removeObserver(paper)
            paper.willMove(toParent: nil)
            paper.view.removeFromSuperview()
            paper.removeFromParent()
        }
        guard let page = document.page(at: index) else { return }
        pageIndex = index
        title = "Trang \(index + 1)/\(document.pageCount)"
        previousItem.isEnabled = index > 0
        nextItem.isEnabled = index < document.pageCount - 1

        let rect = Self.pageRect(page)
        let paper = PaperMarkupViewController(markup: markups[index] ?? PaperMarkup(bounds: rect), supportedFeatureSet: .latest)
        let background = UIImageView(image: page.thumbnail(of: CGSize(width: rect.width * 3, height: rect.height * 3), for: .cropBox))
        background.frame = rect
        paper.contentView = background
        addChild(paper)
        paper.view.frame = view.bounds
        paper.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(paper.view)
        paper.didMove(toParent: self)
        self.paper = paper

        toolPicker.addObserver(paper)
        toolPicker.setVisible(true, forFirstResponder: paper)
        paper.becomeFirstResponder()
    }

    @objc private func previousPage() { showPage(pageIndex - 1) }
    @objc private func nextPage() { showPage(pageIndex + 1) }

    private func showInsertMenu() {
        guard let paper else { return }
        let menu = MarkupEditViewController(supportedFeatureSet: .latest)
        menu.delegate = paper
        menu.modalPresentationStyle = .popover
        menu.popoverPresentationController?.barButtonItem = toolPicker.accessoryItem
        present(menu, animated: true)
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        if let paper { markups[pageIndex] = paper.markup }
        let markups = markups
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task {
            let url = temporaryPDFURL("paperkit")
            guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { return }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                var box = Self.pageRect(page)
                context.beginPage(mediaBox: &box)
                page.draw(with: .cropBox, to: context) // tự áp rotation của trang
                if let markup = markups[index] {
                    // Markup dùng gốc trên-trái như UIKit; PDF context gốc dưới-trái → lật trục Y.
                    context.saveGState()
                    context.translateBy(x: 0, y: box.height)
                    context.scaleBy(x: 1, y: -1)
                    await markup.draw(in: context, frame: box)
                    context.restoreGState()
                }
                context.endPage()
            }
            context.closePDF()
            dismiss(animated: true) { [onSave] in onSave(url) }
        }
    }
}
