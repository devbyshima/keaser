import KeaserKit
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// Where receipt photos come from and what they are for. The expense
/// editor presents the camera or the photo picker for it
/// (`receiptCapture`), whether the title row's scanner asked or the receipt
/// area under the card.
struct ReceiptCaptureRequest: Equatable {
    enum Source { case camera, library }

    enum Purpose {
        /// The title row's scanner or the Scan Receipt control: read into
        /// the empty fields, and kept with the expense if it is a receipt.
        case scan
        /// The receipt area: kept with the expense, and read into the empty
        /// fields when it turns out to be a receipt.
        case attach
    }

    let source: Source
    let purpose: Purpose
    /// How many photos the picker lets the person choose: the room left
    /// under `ReceiptList.maximum`.
    var limit = ReceiptList.maximum

    /// The document camera, where there is one; otherwise only the library.
    @MainActor static var hasCamera: Bool { VNDocumentCameraViewController.isSupported }
}

/// New Expense's way in to receipt scanning: a scanner glyph at the end of
/// the title row, drawn like the row's other trailing glyphs. It offers the
/// document camera and the photo library (straight to the library where
/// there is no camera) and turns into a spinner while the receipt is read.
/// It only asks for a capture; New Expense presents it, fills in its fields
/// and attaches the photo, and the person saves.
struct ReceiptScanButton: View {
    let isReading: Bool
    let onChoose: (ReceiptCaptureRequest.Source) -> Void

    var body: some View {
        Group {
            if isReading {
                ProgressView()
                    .tint(Color.keaserSecondaryText)
                    .accessibilityLabel("Reading Receipt")
            } else if ReceiptCaptureRequest.hasCamera {
                Menu {
                    Button("Scan Receipt", systemImage: "camera") { onChoose(.camera) }
                    Button("Choose Photos", systemImage: "photo.on.rectangle") { onChoose(.library) }
                } label: {
                    glyph
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Scan Receipt")
                .accessibilityHint(Self.hint)
            } else {
                Button {
                    onChoose(.library)
                } label: {
                    glyph
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan Receipt")
                .accessibilityHint(Self.hint)
            }
        }
        .frame(width: 44, height: 44, alignment: .trailing)
    }

    private static let hint = "Fills in the expense from a photo of a receipt."

    private var glyph: some View {
        Image(systemName: "doc.viewfinder")
            .font(.body)
            .foregroundStyle(Color.keaserSecondaryText)
            .frame(width: 44, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Presents the document camera or the photo picker while `request` is
    /// set, then hands over what was captured with the request it answers.
    /// `onCancel` is told when the camera closes without a page.
    func receiptCapture(
        _ request: Binding<ReceiptCaptureRequest?>,
        onCancel: @escaping (ReceiptCaptureRequest) -> Void = { _ in },
        onCapture: @escaping (ReceiptCaptureRequest, ReceiptScanner.Source) -> Void
    ) -> some View {
        modifier(ReceiptCapturePresenter(request: request, onCancel: onCancel, onCapture: onCapture))
    }
}

private struct ReceiptCapturePresenter: ViewModifier {
    @Binding var request: ReceiptCaptureRequest?
    let onCancel: (ReceiptCaptureRequest) -> Void
    let onCapture: (ReceiptCaptureRequest, ReceiptScanner.Source) -> Void

    @State private var photos: [PhotosPickerItem] = []
    /// The request the photo picker answers: the picker clears `request`
    /// as it closes, before the chosen photo arrives.
    @State private var photoRequest: ReceiptCaptureRequest?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: presented(.camera)) {
                DocumentCamera { pages in
                    guard let answered = request else { return }
                    request = nil
                    if pages.isEmpty {
                        onCancel(answered)
                    } else {
                        onCapture(answered, .pages(pages))
                    }
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: presented(.library),
                selection: $photos,
                maxSelectionCount: max(1, request?.limit ?? photoRequest?.limit ?? 1),
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .current
            )
            .onChange(of: request) { _, new in
                if new?.source == .library { photoRequest = new }
            }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty else { return }
                photos = []
                onCapture(photoRequest ?? ReceiptCaptureRequest(source: .library, purpose: .attach), .photos(items))
            }
    }

    private func presented(_ source: ReceiptCaptureRequest.Source) -> Binding<Bool> {
        Binding(
            get: { request?.source == source },
            set: { isPresented in
                if !isPresented, request?.source == source { request = nil }
            }
        )
    }
}

/// VisionKit's document camera: it finds the receipt's edges, flattens it
/// and hands back each page it captured.
private struct DocumentCamera: UIViewControllerRepresentable {
    /// The pages captured, upright; none when the person cancels.
    let onFinish: ([CGImage]) -> Void

    /// Each page becomes a receipt of its own, so no more than an expense
    /// keeps.
    static let maximumPages = ReceiptList.maximum

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onFinish: ([CGImage]) -> Void

        init(onFinish: @escaping ([CGImage]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<min(scan.pageCount, DocumentCamera.maximumPages)).compactMap { scan.imageOfPage(at: $0).uprightCGImage }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onFinish([])
        }
    }
}

private extension UIImage {
    /// The pixels the right way up, whatever orientation the image carries.
    var uprightCGImage: CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }.cgImage
    }
}
