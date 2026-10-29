import UIKit
import PDFKit

/// Lưới thumbnail; nhấn giữ rồi kéo để đổi vị trí trang. Trả về thứ tự mới (index cũ), nil khi Huỷ.
@MainActor
final class PageReorderViewController: UICollectionViewController, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    private let onFinish: ([Int]?) -> Void
    private(set) var order: [Int]
    /// Thumbnail theo index cũ, render nền.
    private var thumbnails: [Int: UIImage] = [:]
    private var renderTask: Task<Void, Never>?

    init(pdf: PDFDocument, onFinish: @escaping ([Int]?) -> Void) {
        self.onFinish = onFinish
        order = Array(0..<pdf.pageCount)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 110, height: 170)
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        super.init(collectionViewLayout: layout)
        title = "Sắp xếp trang"
        // PDFDocument không Sendable: render trên bản sao từ data để không đụng tài liệu đang sửa.
        let data = pdf.dataRepresentation()
        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let data, let copy = PDFDocument(data: data) else { return }
            for index in 0..<copy.pageCount {
                guard !Task.isCancelled else { return }
                let image = copy.page(at: index)?.thumbnail(of: CGSize(width: 220, height: 300), for: .mediaBox)
                await self?.show(image, for: index)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Huỷ", primaryAction: UIAction { [weak self] _ in self?.finish(nil) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Xong", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.finish(self.order)
        })
        navigationItem.prompt = "Nhấn giữ rồi kéo thumbnail để đổi vị trí"
        // Không cho vuốt đóng sheet, tránh nhầm với kéo thumbnail.
        isModalInPresentation = true
        collectionView.backgroundColor = .secondarySystemBackground
        collectionView.register(PageCell.self, forCellWithReuseIdentifier: "page")
        // Drag & drop mặc định tắt trên iPhone.
        installsStandardGestureForInteractiveMovement = false
        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
    }

    private func finish(_ order: [Int]?) {
        renderTask?.cancel()
        onFinish(order)
    }

    private func show(_ image: UIImage?, for index: Int) {
        thumbnails[index] = image
        guard isViewLoaded, let item = order.firstIndex(of: index) else { return }
        (collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? PageCell)?.imageView.image = image
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { order.count }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath) as! PageCell
        let original = order[indexPath.item]
        cell.imageView.image = thumbnails[original]
        cell.label.text = "\(indexPath.item + 1) • gốc \(original + 1)"
        cell.accessibilityLabel = "Vị trí \(indexPath.item + 1), trang gốc \(original + 1)"
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        [UIDragItem(itemProvider: NSItemProvider())]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // Chỉ nhận kéo trong cùng lưới.
        session.localDragSession == nil ? UICollectionViewDropProposal(operation: .forbidden)
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
