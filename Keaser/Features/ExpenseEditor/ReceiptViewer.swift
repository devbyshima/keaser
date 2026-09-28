import CoreTransferable
import KeaserKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A receipt photo full screen: pinch or double-tap to zoom, drag to look
/// around, Close, and Share (the JPEG as kept, named after the expense).
struct ReceiptViewer: View {
    let source: ReceiptImageSource
    /// The expense's title, for the shared file's name and VoiceOver.
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Loaded?
    @State private var missing = false

    private struct Loaded {
        let image: UIImage
        let jpeg: Data
    }

    var body: some View {
        VStack(spacing: 0) {
            KeaserSheetHeader(title: "Receipt") {
                KeaserCircleButton("xmark", label: "Close") { dismiss() }
                    .accessibilityShowsLargeContentViewer { Label("Close", systemImage: "xmark") }
            } trailing: {
                if let loaded {
                    ShareLink(
                        item: ReceiptShareItem(jpeg: loaded.jpeg, fileName: ReceiptShareItem.fileName(for: title)),
                        preview: SharePreview(previewTitle, image: Image(uiImage: loaded.image))
                    ) {
                        KeaserCircleGlyph(symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share Receipt")
                    .accessibilityShowsLargeContentViewer { Label("Share Receipt", systemImage: "square.and.arrow.up") }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ZStack {
                if let loaded {
                    ZoomableImage(image: loaded.image, label: previewTitle)
                        .ignoresSafeArea(edges: .bottom)
                } else if missing {
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
        .background(Color.keaserBackground.ignoresSafeArea())
        .task {
            guard let jpeg = await source.jpeg(), let image = await ReceiptImage.image(of: jpeg) else {
                missing = true
                return
            }
            loaded = Loaded(image: UIImage(cgImage: image), jpeg: jpeg)
        }
    }

    private var previewTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Receipt" : "Receipt for \(trimmed)"
    }
}

/// The receipt as shared: the kept JPEG, which carries no metadata, named
/// after the expense ("Blue Bottle Coffee Receipt.jpg").
struct ReceiptShareItem: Transferable {
    let jpeg: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.jpeg }
            .suggestedFileName { $0.fileName }
    }

    static func fileName(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Receipt.jpg" : "\(cleaned) Receipt.jpg"
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
