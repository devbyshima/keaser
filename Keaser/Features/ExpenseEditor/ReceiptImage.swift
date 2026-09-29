import CoreGraphics
import Foundation
import ImageIO
import KeaserIntelligence
import KeaserKit
import UniformTypeIdentifiers

/// Receipt photos as Keaser keeps them: one JPEG per photo (each page of a
/// scan is its own), at most `maximumPixelSize` on its long side, in sRGB
/// and upright. Only the pixels are kept: the photo's metadata (location,
/// time, camera) never reaches the file.
///
/// Everything here runs away from the main actor.
enum ReceiptImage {
    /// A photo's long side, in pixels: the print stays sharp when zoomed,
    /// and a receipt is a few hundred kilobytes.
    static let maximumPixelSize = 2000
    static let quality = 0.8

    /// The JPEGs to keep for `pages`, one each, in order; a page that
    /// cannot be drawn is left out.
    @concurrent
    static func jpegs(of pages: [CGImage]) async -> [Data] {
        pages.compactMap(makeJPEG(of:))
    }

    /// A thumbnail at most `pixelSize` on its long side, upright.
    @concurrent
    static func thumbnail(of jpeg: Data, pixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The whole photo, decoded.
    @concurrent
    static func image(of jpeg: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Reads a kept photo's file.
    @concurrent
    static func data(of photo: ReceiptPhoto, in folder: ReceiptFolder) async -> Data? {
        folder.data(for: photo)
    }

    /// Deletes kept photos' files (receipts taken off an expense whose edit
    /// was saved).
    @concurrent
    static func remove(_ photos: [ReceiptPhoto], from folder: ReceiptFolder) async {
        folder.remove(photos)
    }

    // MARK: Encoding

    nonisolated static func makeJPEG(of page: CGImage) -> Data? {
        guard let image = redraw(page, longSide: maximumPixelSize) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // No properties besides the quality: nothing of the original
        // photo's metadata is written.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The page drawn afresh on white in sRGB, scaled down to `longSide`
    /// when larger. Drawing keeps only the pixels.
    private nonisolated static func redraw(_ page: CGImage, longSide: Int) -> CGImage? {
        let scale = min(1, CGFloat(longSide) / CGFloat(max(page.width, page.height)))
        let width = max(1, Int((CGFloat(page.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(page.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(page, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

#if DEBUG
extension ReceiptImage {
    /// The samples `-KeaserReceiptAttached <n>` keeps, in order, each a
    /// different shop.
    private static let debugSampleNames = [
        "grocery", "coffee", "cafe-paris", "tip-suggestions", "cash-change",
        "gross-net", "cable", "supermarket-kigali",
    ]

    /// `-KeaserReceiptAttached <n>`: `n` sample receipts (at most
    /// `ReceiptList.maximum`) printed onto paper, kept as scanned ones
    /// would be.
    static func debugSamples(_ value: String) -> [Data] {
        let count = min(max(Int(value) ?? 1, 0), ReceiptList.maximum)
        let samples = debugSampleNames.compactMap(ReceiptSamples.named)
        guard !samples.isEmpty else { return [] }
        return (0..<count).compactMap { index in
            let sample = samples[index % samples.count]
            return ReceiptImageRenderer.image(of: sample.lines, width: 620).flatMap(makeJPEG(of:))
        }
    }
}
#endif
