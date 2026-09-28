import CoreGraphics
import Foundation
import ImageIO
import KeaserIntelligence
import KeaserKit
import UniformTypeIdentifiers

/// Receipt photos as Keaser keeps them: one JPEG per receipt, the pages
/// stacked top to bottom, each page at most `maximumPixelSize` on its long
/// side, in sRGB and upright. Only the pixels are kept: the photo's
/// metadata (location, time, camera) never reaches the file.
///
/// Everything here runs away from the main actor.
enum ReceiptImage {
    /// A page's long side, in pixels: the print stays sharp when zoomed,
    /// and a receipt is a few hundred kilobytes.
    static let maximumPixelSize = 2000
    static let quality = 0.8

    /// The JPEG to keep for `pages`, or nil when there is nothing to keep.
    @concurrent
    static func jpeg(of pages: [CGImage]) async -> Data? {
        makeJPEG(of: pages)
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

    // MARK: Encoding

    nonisolated static func makeJPEG(of pages: [CGImage]) -> Data? {
        let scaled = pages.compactMap { redraw($0, longSide: maximumPixelSize) }
        guard let image = stacked(scaled) else { return nil }
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
        return draw(width: width, height: height) { context in
            context.draw(page, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The pages one under the other at the first page's width, as one
    /// long receipt.
    private nonisolated static func stacked(_ pages: [CGImage]) -> CGImage? {
        guard let first = pages.first else { return nil }
        guard pages.count > 1 else { return first }
        let width = first.width
        let heights = pages.map { Int((CGFloat($0.height) * CGFloat(width) / CGFloat($0.width)).rounded()) }
        let total = heights.reduce(0, +)
        return draw(width: width, height: total) { context in
            // Core Graphics counts from the bottom: the first page goes on top.
            var top = total
            for (page, height) in zip(pages, heights) {
                top -= height
                context.draw(page, in: CGRect(x: 0, y: top, width: width, height: height))
            }
        }
    }

    private nonisolated static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        body(context)
        return context.makeImage()
    }
}

#if DEBUG
extension ReceiptImage {
    /// `-KeaserReceiptAttached`: a sample receipt printed onto paper, kept as
    /// a scanned one would be. `1` is the grocery receipt; any other value
    /// names a `ReceiptSamples` sample.
    static func debugSample(_ value: String) -> Data? {
        let sample = ReceiptSamples.named(value) ?? ReceiptSamples.named("grocery")
        guard let sample, let image = ReceiptImageRenderer.image(of: sample.lines, width: 620) else { return nil }
        return makeJPEG(of: [image])
    }
}
#endif
