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

/// The full-screen viewer to show: every receipt of the expense, opened at
/// one of them.
struct ReceiptViewing: Identifiable {
    let receipts: [ReceiptImageSource]
    let start: Int

    var id: UUID { receipts[start].id }
}

/// A receipt photo filling its frame from the top: a gallery tile, with the
/// card radius, or the small square of a single receipt's row, shaped like
/// the `SymbolTile` of the suggestion rows in the same card. A photo that
/// cannot be read shows a document glyph instead.
struct ReceiptThumbnail: View {
    let source: ReceiptImageSource
    let cornerRadius: CGFloat
    /// The long side to decode, in pixels.
    var pixelSize = 300

    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Color.homeSuggestionTile
            .overlay(alignment: .top) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if missing {
                    Image(systemName: "doc.text.image")
                        .font(.body)
                        .foregroundStyle(Color.keaserSecondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.keaserSeparator, lineWidth: 0.5))
            .accessibilityHidden(true)
            .task(id: source) {
                guard let jpeg = await source.jpeg(), let thumbnail = await ReceiptImage.thumbnail(of: jpeg, pixelSize: pixelSize) else {
                    missing = true
                    return
                }
                image = UIImage(cgImage: thumbnail)
            }
    }
}

/// An expense's receipts when there are two or more, the same in the
/// editor and in the details: two columns of equal portrait tiles at every
/// text size, with the cards' radius and their 16pt spacing, an odd last one
/// in the left column. A tap opens a receipt full screen; in the editor
/// (`onRemove`) a long press offers View and Remove, as a long press on an
/// expense offers Edit and Delete.
struct ReceiptGallery: View {
    let receipts: [ReceiptImageSource]
    let onOpen: (Int) -> Void
    var onRemove: ((ReceiptImageSource) -> Void)?

    var body: some View {
        let spacing = KeaserMetrics.screenPadding
        LazyVGrid(columns: [GridItem(.flexible(), spacing: spacing), GridItem(.flexible(), spacing: spacing)], spacing: spacing) {
            ForEach(Array(receipts.enumerated()), id: \.element.id) { index, source in
                ReceiptTile(
                    source: source,
                    number: index + 1,
                    count: receipts.count,
                    onOpen: { onOpen(index) },
                    onRemove: onRemove.map { remove in { remove(source) } }
                )
                .transition(.opacity)
            }
        }
    }
}

/// One receipt of the gallery. VoiceOver reads it as "Receipt 2 of 3"; a
/// double tap opens it and, in the editor, Remove is one of its actions.
private struct ReceiptTile: View {
    let source: ReceiptImageSource
    let number: Int
    let count: Int
    let onOpen: () -> Void
    let onRemove: (() -> Void)?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: KeaserMetrics.cardRadius, style: .continuous)
    }

    var body: some View {
        Button(action: onOpen) {
            ReceiptThumbnail(source: source, cornerRadius: KeaserMetrics.cardRadius, pixelSize: 800)
                .aspectRatio(3 / 4, contentMode: .fit)
                .contentShape(shape)
        }
        .buttonStyle(PressScaleButtonStyle())
        .contentShape(.contextMenuPreview, shape)
        .contextMenu {
            if let onRemove {
                ReceiptMenu(onOpen: onOpen, onRemove: onRemove)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Receipt \(number) of \(count)")
        .accessibilityAddTraits([.isButton, .isImage])
        .accessibilityAction { onOpen() }
        .accessibilityActions {
            if let onRemove {
                Button("Remove", action: onRemove)
            }
        }
    }
}

/// A receipt's long-press menu in the editor, as an expense's is: View,
/// then Remove (which asks first).
private struct ReceiptMenu: View {
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label("View", systemImage: "doc.text.magnifyingglass")
        }
        Button(role: .destructive, action: onRemove) {
            Label("Remove", systemImage: "trash")
        }
    }
}

/// A single receipt as a card row, built like the editor's suggestion rows:
/// its thumbnail, View Receipt and a chevron. In the editor a long press
/// offers View and Remove.
struct ReceiptRow: View {
    let source: ReceiptImageSource
    let onOpen: () -> Void
    var onRemove: (() -> Void)?

    static let thumbnailSize: CGFloat = 30

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ReceiptThumbnail(source: source, cornerRadius: Self.thumbnailSize * 0.3)
                    .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                Text("View Receipt")
                    .font(.body)
                    .foregroundStyle(Color.keaserPrimaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.keaserTertiaryText)
                    .accessibilityHidden(true)
            }
            .receiptRow()
        }
        .buttonStyle(HighlightRowButtonStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: KeaserMetrics.rowRadius, style: .continuous))
        .contextMenu {
            if let onRemove {
                ReceiptMenu(onOpen: onOpen, onRemove: onRemove)
            }
        }
        .accessibilityLabel("View Receipt")
        .accessibilityHint("Opens the photo of the receipt.")
        .accessibilityActions {
            if let onRemove {
                Button("Remove", action: onRemove)
            }
        }
    }
}

/// Under the expense editor's card: the receipts (`ReceiptRow` for one,
/// `ReceiptGallery` for more), then Add Receipt in a card, drawn like Add
/// Account: one menu for the camera and the photo library. It goes away at
/// `ReceiptList.maximum`.
struct ReceiptAttachmentSection: View {
    let receipts: [ReceiptImageSource]
    /// Photos being made ready to keep.
    let isPreparing: Bool
    let onChoose: (ReceiptCaptureRequest.Source) -> Void
    let onOpen: (Int) -> Void
    let onRemove: (ReceiptImageSource) -> Void

    private var canAdd: Bool { ReceiptList.room(after: receipts.count) > 0 }

    var body: some View {
        VStack(spacing: KeaserMetrics.screenPadding) {
            if receipts.count > 1 {
                ReceiptGallery(receipts: receipts, onOpen: onOpen, onRemove: onRemove)
            }
            if receipts.count == 1 || isPreparing || canAdd {
                KeaserCard(fill: .homeSheetCard) {
                    if receipts.count == 1, let only = receipts.first {
                        ReceiptRow(source: only, onOpen: { onOpen(0) }) { onRemove(only) }
                        if isPreparing || canAdd {
                            KeaserRowSeparator(leading: 16 + ReceiptRow.thumbnailSize + 12)
                        }
                    }
                    if isPreparing {
                        preparingRow
                    } else if canAdd {
                        addRow
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addRow: some View {
        if ReceiptCaptureRequest.hasCamera {
            Menu {
                Button("Scan Receipt", systemImage: "camera") { onChoose(.camera) }
                Button("Choose Photos", systemImage: "photo.on.rectangle") { onChoose(.library) }
            } label: {
                addLabel
            }
            .menuOrder(.fixed)
            .accessibilityHint(Self.addHint)
        } else {
            Button {
                onChoose(.library)
            } label: {
                addLabel
            }
            .buttonStyle(HighlightRowButtonStyle())
            .accessibilityHint(Self.addHint)
        }
    }

    private static let addHint = "Keeps a photo of a receipt with this expense."

    /// As Add Account draws its row.
    private var addLabel: some View {
        Text("Add Receipt")
            .font(.body.weight(.medium))
            .foregroundStyle(Color.keaserPrimaryText)
            .receiptRow()
            .contentShape(Rectangle())
    }

    private var preparingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.keaserSecondaryText)
            Text("Adding Receipt\u{2026}")
                .font(.body)
                .foregroundStyle(Color.keaserSecondaryText)
            Spacer(minLength: 0)
        }
        .receiptRow()
        .accessibilityElement(children: .combine)
    }
}

/// The receipts under an expense's details, opening full screen: one as a
/// row in a card, more as the gallery.
struct ReceiptDetailSection: View {
    let receipts: [ReceiptPhoto]
    let onOpen: (Int) -> Void

    var body: some View {
        if receipts.count == 1, let only = receipts.first {
            KeaserCard(fill: .homeSheetCard) {
                ReceiptRow(source: .saved(only)) { onOpen(0) }
            }
        } else if receipts.count > 1 {
            ReceiptGallery(receipts: receipts.map(ReceiptImageSource.saved), onOpen: onOpen)
        }
    }
}

private extension View {
    /// A card row as the editor's and Add Account's: 16pt in from the
    /// card's sides, `HomeSheetMetrics.rowHeight` tall at least.
    func receiptRow() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: HomeSheetMetrics.rowHeight, alignment: .leading)
    }
}
