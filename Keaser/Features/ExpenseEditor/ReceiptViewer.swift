import CoreTransferable
import KeaserKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// An expense's receipts full screen, opened at one of them, with the
/// header every sheet has: Close (the xmark circle) on the left, the title
/// ("Receipt 2 of 3" when there are several), Share on the right. Swipe
/// between the receipts; pinch or double-tap to zoom and drag to look
/// around. Opened from the editor (`onRemove`), Remove Receipt sits under
/// the photo in a card of its own, as Delete Expense does under an
/// expense, and asks first.
struct ReceiptViewer: View {
    /// The expense's title, for the shared file's name and VoiceOver.
    let title: String
    let onRemove: ((ReceiptImageSource) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var receipts: [ReceiptImageSource]
    @State private var index: Int
    @State private var jpegs: [UUID: Data] = [:]
    @State private var images: [UUID: UIImage] = [:]
    @State private var missing: Set<UUID> = []
    @State private var confirmingRemove = false

    init(_ viewing: ReceiptViewing, title: String, onRemove: ((ReceiptImageSource) -> Void)? = nil) {
        self.title = title
        self.onRemove = onRemove
        _receipts = State(initialValue: viewing.receipts)
        _index = State(initialValue: min(max(viewing.start, 0), max(viewing.receipts.count - 1, 0)))
    }

    private var current: ReceiptImageSource? {
        receipts.indices.contains(index) ? receipts[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: name(index)) {
                KeaserCircleButton("xmark", label: "Close") { dismiss() }
                    .accessibilityShowsLargeContentViewer { Label("Close", systemImage: "xmark") }
            } trailing: {
                shareButton
            }
            .homeSheetHeader()
            TabView(selection: $index) {
                ForEach(Array(receipts.enumerated()), id: \.element.id) { number, source in
                    page(source, number: number)
                        .tag(number)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .padding(.top, KeaserMetrics.screenPadding)
            if onRemove != nil {
                // On the screen's own background, as Home's cards are.
                KeaserActionCard("Remove Receipt", role: .destructive, fill: .keaserCard) { confirmingRemove = true }
                    .padding(.horizontal, KeaserMetrics.screenPadding)
                    .padding(.top, KeaserMetrics.screenPadding)
            }
        }
        .background(Color.keaserBackground.ignoresSafeArea())
        .task { await load() }
        .confirmationDialog("Remove Receipt?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove Receipt", role: .destructive, action: removeCurrent)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let current {
                Text(Self.removalMessage(for: current, in: receipts))
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let current, let jpeg = jpegs[current.id] {
            let item = ReceiptShareItem(jpeg: jpeg, fileName: ReceiptShareItem.fileName(for: title, number: receipts.count > 1 ? index + 1 : nil))
            Group {
                if let image = images[current.id] {
                    ShareLink(item: item, preview: SharePreview(label(index), image: Image(uiImage: image))) {
                        KeaserCircleGlyph(symbol: "square.and.arrow.up")
                    }
                } else {
                    ShareLink(item: item, preview: SharePreview(label(index))) {
                        KeaserCircleGlyph(symbol: "square.and.arrow.up")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share Receipt")
            .accessibilityShowsLargeContentViewer { Label("Share Receipt", systemImage: "square.and.arrow.up") }
        }
    }

    @ViewBuilder
    private func page(_ source: ReceiptImageSource, number: Int) -> some View {
        ZStack {
            if let image = images[source.id] {
                ZoomableImage(image: image, label: label(number))
            } else if missing.contains(source.id) {
                EmptyStateView(
                    symbol: "doc.text.image",
                    title: "Receipt Unavailable",
                    message: "The photo of this receipt couldn't be opened."
                )
            } else {
                ProgressView()
                    .tint(Color.keaserSecondaryText)
                    .accessibilityLabel("Opening Receipt")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Receipt 2 of 3", or "Receipt" alone.
    private func name(_ number: Int) -> String {
        Self.name(number, of: receipts.count)
    }

    private static func name(_ number: Int, of count: Int) -> String {
        count > 1 ? "Receipt \(number + 1) of \(count)" : "Receipt"
    }

    /// "Receipt 2 of 3 for Coffee", for VoiceOver and the share sheet.
    private func label(_ number: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name(number) : "\(name(number)) for \(trimmed)"
    }

    /// Under "Remove Receipt?", naming the receipt in quotes as Delete
    /// Expense names the expense.
    static func removalMessage(for source: ReceiptImageSource, in receipts: [ReceiptImageSource]) -> String {
        let number = receipts.firstIndex(of: source) ?? 0
        return "\u{201C}\(name(number, of: receipts.count))\u{201D} will be removed from this expense when you save."
    }

    private func removeCurrent() {
        guard let current else { return }
        onRemove?(current)
        withAnimation(.smooth(duration: 0.3)) {
            receipts.removeAll { $0 == current }
            index = min(index, max(receipts.count - 1, 0))
        }
        if receipts.isEmpty { dismiss() }
    }

    /// The receipt opened first, then its neighbours outwards.
    private func load() async {
        let order = receipts.indices.sorted { abs($0 - index) < abs($1 - index) }
        for position in order {
            let source = receipts[position]
            guard let jpeg = await source.jpeg(), let image = await ReceiptImage.image(of: jpeg) else {
                missing.insert(source.id)
                continue
            }
            jpegs[source.id] = jpeg
            images[source.id] = UIImage(cgImage: image)
        }
    }
}

/// A receipt as shared: the kept JPEG, which carries no metadata, named
/// after the expense ("Blue Bottle Coffee Receipt.jpg", or "Dinner
/// Receipt 2.jpg" for one of several).
struct ReceiptShareItem: Transferable {
    let jpeg: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.jpeg }
            .suggestedFileName { $0.fileName }
    }

    static func fileName(for title: String, number: Int? = nil) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let name = cleaned.isEmpty ? "Receipt" : "\(cleaned) Receipt"
        return number.map { "\(name) \($0).jpg" } ?? "\(name).jpg"
    }
}

/// The photo in a scroll view that zooms: it opens fitted to the screen,
/// pinches up to five times closer (or to its full size), and a double tap
/// zooms in on that point or back out.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let label: String

    func makeUIView(context: Context) -> ZoomingImageView {
        ZoomingImageView(image: image, label: label)
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {}
}

private final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    /// The bounds the zoom scales were last worked out for.
    private var fittedSize: CGSize = .zero

    init(image: UIImage, label: String) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        bouncesZoom = true

        imageView.frame = CGRect(origin: .zero, size: image.size)
        // A photo stays as it is under Smart Invert.
        imageView.accessibilityIgnoresInvertColors = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = label
        imageView.accessibilityTraits = .image
        addSubview(imageView)
        contentSize = image.size

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        if size != fittedSize, size.width > 0, size.height > 0, let image = imageView.image {
            fittedSize = size
            let fit = min(size.width / image.size.width, size.height / image.size.height)
            minimumZoomScale = fit
            maximumZoomScale = max(fit * 5, 1)
            zoomScale = fit
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    /// Keeps a photo smaller than the screen in the middle of it.
    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale = min(maximumZoomScale, minimumZoomScale * 3)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
