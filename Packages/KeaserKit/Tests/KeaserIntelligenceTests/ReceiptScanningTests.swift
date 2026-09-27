import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
@testable import KeaserIntelligence
import KeaserKit
import Testing
import UniformTypeIdentifiers

/// Receipt scanning's device side without the model: Vision reading a
/// printed receipt back into lines, preparing a picked photo, and the shape
/// the model answers in.
@MainActor
struct ReceiptScanningTests {
    @Test(arguments: ["grocery", "cafe-paris", "supermarket-kigali"])
    func visionReadsAPrintedReceiptBack(_ name: String) async throws {
        let sample = try #require(ReceiptSamples.named(name))
        let image = try #require(ReceiptImageRenderer.image(of: sample.lines))
        let lines = try await ReceiptTextRecognizer.lines(in: image)
        let draft = ReceiptParser.draft(from: lines, today: ReceiptSamples.today, prefersMonthFirst: true)
        #expect(draft == sample.expected, "read \(lines)")
    }

    @Test func aPickedPhotoIsScaledDownAndTurnedUpright() throws {
        // 3000 by 1000 pixels, stored turned a quarter (EXIF orientation 6).
        let context = try #require(CGContext(
            data: nil, width: 3000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let prepared = try #require(ReceiptTextRecognizer.image(from: data as Data))
        #expect(max(prepared.width, prepared.height) == ReceiptTextRecognizer.maximumPixelSize)
        #expect(prepared.height > prepared.width)
        #expect(ReceiptTextRecognizer.image(from: Data("not an image".utf8)) == nil)
    }

    @Test func aBlankPageHasNoLines() async throws {
        let blank = try #require(ReceiptImageRenderer.image(of: []))
        #expect(await ReceiptTextRecognizer.lines(in: [blank]).isEmpty)
    }

    @Test func theModelsAnswerMapsToTheChecks() throws {
        guard #available(macOS 26.0, *) else { return }
        let content = GeneratedContent(properties: [
            "merchant": "Café de Flore",
            "total": "14,50 €",
            "date": GeneratedContent(properties: ["year": 2026, "month": 4, "day": 3]),
            "currency": "EUR",
        ])
        let fields = try ReceiptFields(content)
        #expect(fields.answer == ReceiptModelAnswer(merchant: "Café de Flore", total: "14,50 €", year: 2026, month: 4, day: 3, currency: "EUR"))
        let empty = try ReceiptFields(GeneratedContent(properties: [:]))
        #expect(empty.answer == ReceiptModelAnswer())
    }

    @Test func itIsGreedyAndOnDevice() async {
        guard #available(macOS 26.0, *) else {
            #expect(AppleIntelligence.receiptModel == nil)
            return
        }
        #expect(OnDeviceReceiptModel.options.samplingMode == .greedy)
        #expect(AppleIntelligence.receiptModel != nil)
        #expect(OnDeviceReceiptModel.shared.isReady == AppleIntelligence.isReady)
        #expect(await OnDeviceReceiptModel().read(ReceiptPrompt.prefix + "TOTAL 4.00", within: .zero) == nil)
    }
}
