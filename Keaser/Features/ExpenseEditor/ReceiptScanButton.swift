import KeaserKit
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// New Expense's way in to receipt scanning: a scanner glyph at the end of
/// the title row, drawn like the row's other trailing glyphs. It offers the
/// document camera and the photo library (straight to the library where
/// there is no camera) and turns into a spinner while the receipt is read.
/// It only hands over what was scanned; New Expense fills in its fields and
/// the person saves.
struct ReceiptScanButton: View {
    let isReading: Bool
    /// Just before the camera or the photo picker opens.
    let onOpen: () -> Void
    let onScan: (ReceiptScanner.Source) -> Void

    @State private var scanning = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?

    private let hasCamera = VNDocumentCameraViewController.isSupported

    var body: some View {
        Group {
            if isReading {
                ProgressView()
                    .tint(Color.keaserSecondaryText)
                    .accessibilityLabel("Reading Receipt")
            } else if hasCamera {
                Menu {
                    Button("Scan Receipt", systemImage: "camera") { open { scanning = true } }
                    Button("Choose Photo", systemImage: "photo.on.rectangle") { open { choosingPhoto = true } }
                } label: {
                    glyph
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Scan Receipt")
                .accessibilityHint(Self.hint)
            } else {
                Button {
                    open { choosingPhoto = true }
                } label: {
                    glyph
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan Receipt")
                .accessibilityHint(Self.hint)
            }
        }
        .frame(width: 44, height: 44, alignment: .trailing)
        .fullScreenCover(isPresented: $scanning) {
            DocumentCamera { pages in
                scanning = false
                if !pages.isEmpty { onScan(.pages(pages)) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images, preferredItemEncoding: .current)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            onScan(.photo(item))
        }
    }

    private static let hint = "Fills in the expense from a photo of a receipt."

    private var glyph: some View {
        Image(systemName: "doc.viewfinder")
            .font(.body)
            .foregroundStyle(Color.keaserSecondaryText)
            .frame(width: 44, height: 44, alignment: .trailing)
            .contentShape(Rectangle())
    }

    private func open(_ present: () -> Void) {
        onOpen()
        present()
    }
}

/// VisionKit's document camera: it finds the receipt's edges, flattens it
/// and hands back each page it captured.
private struct DocumentCamera: UIViewControllerRepresentable {
    /// The pages captured, upright; none when the person cancels.
    let onFinish: ([CGImage]) -> Void

    /// A long receipt can take a few pages; more is not a receipt.
    static let maximumPages = 4

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
