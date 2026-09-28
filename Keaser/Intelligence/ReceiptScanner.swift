import KeaserIntelligence
import KeaserKit
import PhotosUI
import SwiftUI

/// Receipt scanning for New Expense: reads the pages the document camera
/// captured, or the photo the person picked, into a `ReceiptDraft` for them
/// to check. Everything happens on the iPhone and reading saves nothing:
/// New Expense keeps the photo with the expense (`ReceiptImage`) only when
/// the person saves it.
///
/// Vision reads the text on every system. On iOS 26 and later, with Apple
/// Intelligence ready, the on-device model reads it too, and its answers are
/// kept only where the receipt's text backs them up (`ReceiptReading`). In
/// DEBUG, `-KeaserCategoryModel off` stands for an iPhone without Apple
/// Intelligence here as well.
@MainActor
enum ReceiptScanner {
    /// What was scanned.
    enum Source {
        case pages([CGImage])
        case photo(PhotosPickerItem)
        /// Text already read, for DEBUG samples.
        case lines([String])
    }

    static var model: (any ReceiptModel)? {
        #if DEBUG
        if DebugLaunch.string("KeaserCategoryModel") == "off" { return nil }
        #endif
        return AppleIntelligence.receiptModel
    }

    /// Loads the model while the camera or the photo picker is open, so the
    /// receipt is read without that wait.
    static func prewarm() {
        guard let model, model.isReady else { return }
        model.prewarm()
    }

    /// The pages of what was scanned, upright: the camera's pages as they
    /// are, or the picked photo scaled down (`ReceiptTextRecognizer.image(from:)`).
    /// None for a photo that is not an image, or for text-only DEBUG samples.
    static func pages(of source: Source) async -> [CGImage] {
        switch source {
        case .pages(let pages):
            return pages
        case .photo(let item):
            guard let data = try? await item.loadTransferable(type: Data.self) else { return [] }
            return await upright(data).map { [$0] } ?? []
        case .lines:
            return []
        }
    }

    @concurrent
    private nonisolated static func upright(_ photo: Data) async -> CGImage? {
        ReceiptTextRecognizer.image(from: photo)
    }

    /// The receipt's details. Dates are read the way this iPhone's region
    /// writes them unless the receipt settles it, and none after `now`.
    static func read(_ source: Source, calendar: Calendar, now: Date = .now) async -> ReceiptDraft {
        let lines: [String]
        switch source {
        case .pages, .photo:
            lines = await ReceiptTextRecognizer.lines(in: pages(of: source))
        case .lines(let text):
            lines = text
        }
        return await ReceiptReading.read(
            lines,
            model: model,
            today: ReceiptDay(now, calendar: calendar),
            prefersMonthFirst: ReceiptParser.prefersMonthFirst()
        )
    }
}

#if DEBUG
extension ReceiptScanner {
    /// `-KeaserReceipt <sample>` reads one of `ReceiptSamples` as if it had
    /// just been scanned; with `-KeaserReceiptImage 1` the sample is printed
    /// onto an image first and read with Vision, the whole way a photo goes.
    static var debugSource: Source? {
        guard let name = DebugLaunch.string("KeaserReceipt"), let sample = ReceiptSamples.named(name) else { return nil }
        if DebugLaunch.string("KeaserReceiptImage") == "1", let image = ReceiptImageRenderer.image(of: sample.lines) {
            return .pages([image])
        }
        return .lines(sample.lines)
    }

    /// `-KeaserReceiptHold 1` keeps the receipt reading, to screenshot that.
    static var holdsReading: Bool { DebugLaunch.string("KeaserReceiptHold") == "1" }
}
#endif
