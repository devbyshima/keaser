import CoreGraphics
import Foundation
import ImageIO
import KeaserKit
import Vision

/// Reads the text on a receipt photo with Vision, on the device, and hands
/// back the receipt's lines top to bottom (see `ReceiptText`). The image is
/// only held in memory while it is read; nothing is kept or sent anywhere.
///
/// iOS 26 and later use Vision's document reader (`RecognizeDocumentsRequest`),
/// earlier systems its text reader (`RecognizeTextRequest`).
public enum ReceiptTextRecognizer {
    /// Photos are scaled down to this many pixels on their long side: plenty
    /// for a receipt's print, and a 48-megapixel photo never sits in memory
    /// whole.
    public static let maximumPixelSize = 2400

    /// A picked photo, upright and scaled down; nil when it is not an image.
    public static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The lines of text on every page, in order. A page that cannot be
    /// read adds nothing.
    public static func lines(in pages: [CGImage]) async -> [String] {
        var lines: [String] = []
        for page in pages {
            lines += (try? await self.lines(in: page)) ?? []
        }
        return lines
    }

    /// The lines of text on one upright image.
    public static func lines(in image: CGImage) async throws -> [String] {
        let size = CGSize(width: image.width, height: image.height)
        if #available(iOS 26.0, macOS 26.0, *) {
            if let fragments = try? await documentFragments(in: image, size: size), !fragments.isEmpty {
                return ReceiptText.lines(from: fragments)
            }
        }
        return ReceiptText.lines(from: try await textFragments(in: image, size: size))
    }

    // MARK: Requests

    @available(iOS 26.0, macOS 26.0, *)
    private static func documentFragments(in image: CGImage, size: CGSize) async throws -> [ReceiptText.Fragment] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.barcodeDetectionOptions.enabled = false
        let documents = try await request.perform(on: image)
        return documents.flatMap { $0.document.text.lines }.compactMap { fragment($0, size: size) }
    }

    private static func textFragments(in image: CGImage, size: CGSize) async throws -> [ReceiptText.Fragment] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        return try await request.perform(on: image).compactMap { fragment($0, size: size) }
    }

    /// A line Vision found, with its corners in image points so a tilted
    /// photo keeps its real slope.
    private static func fragment(_ observation: RecognizedTextObservation, size: CGSize) -> ReceiptText.Fragment? {
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        func point(_ normalized: NormalizedPoint) -> CGPoint {
            CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
        }
        return ReceiptText.Fragment(
            text: text,
            topLeft: point(observation.topLeft),
            topRight: point(observation.topRight),
            bottomRight: point(observation.bottomRight),
            bottomLeft: point(observation.bottomLeft)
        )
    }
}
