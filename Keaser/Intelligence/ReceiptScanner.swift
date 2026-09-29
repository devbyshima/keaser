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
    /// What was scanned: the document camera's pages, or the photos picked
    /// from the library, in order.
    enum Source {
        case pages([CGImage])
        case photos([PhotosPickerItem])
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

    /// The pages of what was scanned, upright and in order: the camera's
    /// pages as they are, or each picked photo scaled down
    /// (`ReceiptTextRecognizer.image(from:)`). A photo that is not an image
    /// is left out; text-only DEBUG samples have none.
    static func pages(of source: Source) async -> [CGImage] {
        switch source {
        case .pages(let pages):
            return pages
        case .photos(let items):
            var pages: [CGImage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self), let page = await upright(data) else { continue }
                pages.append(page)
            }
            return pages
        case .lines:
            return []
        }
    }

    @concurrent
    private nonisolated static func upright(_ photo: Data) async -> CGImage? {
        ReceiptTextRecognizer.image(from: photo)
    }

    /// The receipt's details, its pages read together in order as one
    /// receipt (`ReceiptReading.read(pages:)`). Dates are read the way this
    /// iPhone's region writes them unless the receipt settles it, and none
    /// after `now`.
    static func read(_ pages: [CGImage], calendar: Calendar, now: Date = .now) async -> ReceiptDraft {
        var lines: [[String]] = []
        for page in pages {
            lines.append((try? await ReceiptTextRecognizer.lines(in: page)) ?? [])
        }
        return await read(lines: lines, calendar: calendar, now: now)
    }

    /// Text already read (DEBUG samples), as one page.
    static func read(lines: [[String]], calendar: Calendar, now: Date = .now) async -> ReceiptDraft {
        await ReceiptReading.read(
            pages: lines,
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
