import KeaserKit
import SwiftUI
import UIKit

/// A receipt photo to show: one kept with an expense, or one just attached
/// in the editor and not saved yet.
enum ReceiptImageSource: Hashable, Identifiable, Sendable {
    case saved(ReceiptPhoto)
    case unsaved(UnsavedReceipt)

    var id: UUID {
        switch self {
        case .saved(let photo): photo.id
        case .unsaved(let receipt): receipt.id
        }
    }

    /// The photo's JPEG, read away from the main actor; nil when a kept
    /// photo's file is missing.
    func jpeg() async -> Data? {
        switch self {
        case .saved(let photo): await ReceiptImage.data(of: photo, in: AppEnvironment.receipts)
        case .unsaved(let receipt): receipt.jpeg
        }
    }
}

/// A photo attached in the expense editor. It stays in memory until Save
/// writes it to the Receipts folder, so Cancel leaves no file behind.
struct UnsavedReceipt: Hashable, Sendable {
    let id = UUID()
    let jpeg: Data

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What the expense editor has for the receipt.
enum ReceiptAttachment: Equatable {
    case none
    /// A photo being scaled down and compressed; Save waits for it.
    case preparing
    case attached(ReceiptImageSource)
}

/// A receipt photo's thumbnail: the top of the receipt filling a rounded
/// square, as an attachment is shown in a list. A photo that cannot be read
/// shows a document glyph instead.
struct ReceiptThumbnail: View {
    let source: ReceiptImageSource
    var size: CGFloat = 36

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            shape.fill(Color.homeSuggestionTile)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size, alignment: .top)
                    .clipped()
            } else if missing {
                Image(systemName: "doc.text.image")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color.keaserSecondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.keaserSeparator, lineWidth: 0.5))
        .accessibilityHidden(true)
        .task(id: source) {
            let pixels = Int((size * displayScale * 3).rounded())
            guard let jpeg = await source.jpeg(), let thumbnail = await ReceiptImage.thumbnail(of: jpeg, pixelSize: pixels) else {
                missing = true
                return
            }
            image = UIImage(cgImage: thumbnail)
        }
    }
}

/// Under the expense editor's card: a quiet "Attach Receipt" row while the
/// expense has no photo (the camera or the photo library, from one menu),
/// and the photo with View and Remove once it has one. Its rows are as tall
/// as the card's.
struct ReceiptAttachmentSection: View {
    let attachment: ReceiptAttachment
    let rowHeight: CGFloat
    let onChoose: (ReceiptCaptureRequest.Source) -> Void
    let onView: (ReceiptImageSource) -> Void
    let onRemove: () -> Void

    var body: some View {
        KeaserCard(fill: .homeSheetCard) {
            switch attachment {
            case .none:
                attachRow
            case .preparing:
                preparingRow
            case .attached(let source):
                attachedRow(source)
            }
        }
    }

    @ViewBuilder
    private var attachRow: some View {
        if ReceiptCaptureRequest.hasCamera {
            Menu {
                Button("Scan Receipt", systemImage: "camera") { onChoose(.camera) }
                Button("Choose Photo", systemImage: "photo.on.rectangle") { onChoose(.library) }
            } label: {
                attachLabel
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Attach Receipt")
            .accessibilityHint(Self.attachHint)
        } else {
            Button {
                onChoose(.library)
            } label: {
                attachLabel
            }
            .buttonStyle(HighlightRowButtonStyle())
            .accessibilityLabel("Attach Receipt")
            .accessibilityHint(Self.attachHint)
        }
    }

    private static let attachHint = "Keeps a photo of the receipt with this expense."

    /// The glyph sits where the thumbnail will, so the label does not move
    /// once a photo is attached.
    private var attachLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperclip")
                .font(.body)
                .foregroundStyle(Color.keaserSecondaryText)
                .frame(width: 36)
            Text("Attach Receipt")
                .font(.body)
                .foregroundStyle(Color.keaserPrimaryText)
            Spacer(minLength: 0)
        }
        .receiptRow(height: rowHeight)
        .contentShape(Rectangle())
    }

    private var preparingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.keaserSecondaryText)
                .frame(width: 36, height: 36)
            Text("Attaching Receipt\u{2026}")
                .font(.body)
                .foregroundStyle(Color.keaserSecondaryText)
            Spacer(minLength: 0)
        }
        .receiptRow(height: rowHeight)
        .accessibilityElement(children: .combine)
    }

    private func attachedRow(_ source: ReceiptImageSource) -> some View {
        HStack(spacing: 12) {
            Button {
                onView(source)
            } label: {
                HStack(spacing: 12) {
                    ReceiptThumbnail(source: source)
                    Text("View Receipt")
                        .font(.body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View Receipt")
            .accessibilityHint("Opens the photo of the receipt.")
            // Red, like Delete Expense, and readable where Home's + button
            // shows through the glass sheet at the trailing edge.
            Button("Remove", action: onRemove)
                .font(.body)
                .foregroundStyle(Color.keaserDestructive)
                .fixedSize()
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Remove Receipt")
        }
        .receiptRow(height: rowHeight)
    }
}

/// The receipt under an expense's details: its thumbnail, opening the
/// photo full screen.
struct ReceiptDetailRow: View {
    let photo: ReceiptPhoto
    let onView: () -> Void

    var body: some View {
        KeaserCard(fill: .homeSheetCard) {
            Button(action: onView) {
                HStack(spacing: 12) {
                    ReceiptThumbnail(source: .saved(photo))
                    Text("View Receipt")
                        .font(.body)
                        .foregroundStyle(Color.keaserPrimaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.keaserTertiaryText)
                }
                .receiptRow(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(HighlightRowButtonStyle())
            .accessibilityLabel("View Receipt")
            .accessibilityHint("Opens the photo of the receipt.")
        }
    }
}

private extension View {
    func receiptRow(height: CGFloat) -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }
}
