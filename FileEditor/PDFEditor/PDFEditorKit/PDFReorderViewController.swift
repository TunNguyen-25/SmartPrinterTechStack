import UIKit
import PDFKit

/// Lưới thumbnail; nhấn giữ rồi kéo để đổi vị trí trang (drag & drop của UICollectionView).
final class PDFReorderViewController: UICollectionViewController, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    private let document: PDFDocument
    private let onSave: @MainActor (URL) -> Void
    private var order: [Int]

    init(document: PDFDocument, onSave: @escaping @MainActor (URL) -> Void) {
        self.document = document
        self.onSave = onSave
        order = Array(0..<document.pageCount)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 110, height: 170)
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        super.init(collectionViewLayout: layout)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addCancelSave(save: #selector(save))
        navigationItem.prompt = "Nhấn giữ rồi kéo thumbnail để đổi vị trí"
        collectionView.backgroundColor = .secondarySystemBackground
        collectionView.register(PageCell.self, forCellWithReuseIdentifier: "page")
        // Gesture reorder có sẵn của UICollectionViewController không chạy ở đây; dùng drag & drop (mặc định tắt trên iPhone).
        installsStandardGestureForInteractiveMovement = false
        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { order.count }

    // ponytail: render thumbnail đồng bộ khi hiện cell; chuyển sang render nền + cache nếu PDF hàng trăm trang bị giật.
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath) as! PageCell
        let original = order[indexPath.item]
        cell.imageView.image = document.page(at: original)?.thumbnail(of: CGSize(width: 220, height: 300), for: .cropBox)
        cell.label.text = "\(indexPath.item + 1) • gốc \(original + 1)"
        cell.accessibilityLabel = "Vị trí \(indexPath.item + 1), trang gốc \(original + 1)"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        return [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // Chỉ nhận kéo trong cùng lưới.
        return session.localDragSession == nil ? UICollectionViewDropProposal(operation: .forbidden)
            : UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first, let source = item.sourceIndexPath else { return }
        let destination = coordinator.destinationIndexPath ?? IndexPath(item: order.count - 1, section: 0)
        collectionView.performBatchUpdates {
            order.insert(order.remove(at: source.item), at: destination.item)
            collectionView.moveItem(at: source, to: destination)
        } completion: { _ in collectionView.reloadData() } // cập nhật nhãn vị trí
        coordinator.drop(item.dragItem, toItemAt: destination)
    }

    @objc private func save() {
        let pages = order.compactMap(document.page(at:))
        // Đưa lần lượt từng trang về vị trí i; các trang chưa xếp luôn nằm ở chỉ số >= i.
        for (i, page) in pages.enumerated() {
            document.removePage(at: document.index(for: page))
            document.insert(page, at: i)
        }
        finish(writing: document, prefix: "reorder", onSave: onSave)
    }
}

private final class PageCell: UICollectionViewCell {
    let imageView = UIImageView()
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        imageView.contentMode = .scaleAspectFit
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .vertical)
        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .vertical
        stack.spacing = 4
        stack.frame = contentView.bounds
        stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(stack)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
