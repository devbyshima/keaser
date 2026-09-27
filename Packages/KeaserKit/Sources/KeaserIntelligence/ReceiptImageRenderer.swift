#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import KeaserKit

/// Prints a sample receipt's text onto an image the way a till would: the
/// shop's name centred at the top, labels on the left and amounts on the
/// right, in a monospaced face on white paper. DEBUG only: New Expense's
/// `-KeaserReceiptImage` screenshots and the evaluation read these through
/// Vision, so the whole path runs without a camera.
public enum ReceiptImageRenderer {
    public static func image(of lines: [String], width: Int = 900) -> CGImage? {
        let fontSize: CGFloat = 30
        let lineHeight = Int(fontSize * 1.55)
        let margin: CGFloat = 60
        let height = lineHeight * (lines.count + 4)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        let ink = CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        func draw(_ text: String, at x: CGFloat, baseline: CGFloat, alignment: CGFloat) {
            let attributed = CFAttributedStringCreate(nil, text as CFString, [
                kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink,
            ] as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attributed)
            let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            context.textPosition = CGPoint(x: x - textWidth * alignment, y: baseline)
            CTLineDraw(line, context)
        }

        // The heading (name, address, phone) is centred down to the first price.
        let firstPrice = lines.firstIndex { ReceiptParser.amounts(in: $0).contains(where: \.looksLikeMoney) } ?? 1
        for (index, line) in lines.enumerated() {
            let baseline = CGFloat(height - lineHeight * (index + 2))
            if index < max(firstPrice, 1) {
                draw(line, at: CGFloat(width) / 2, baseline: baseline, alignment: 0.5)
            } else if let (label, amount) = split(line) {
                draw(label, at: margin, baseline: baseline, alignment: 0)
                draw(amount, at: CGFloat(width) - margin, baseline: baseline, alignment: 1)
            } else {
                draw(line, at: margin, baseline: baseline, alignment: 0)
            }
        }
        return context.makeImage()
    }

    /// "Total TTC 14,50 €" is "Total TTC" and "14,50 €": the last amount on
    /// a line with a label, and a currency printed next to it.
    static func split(_ line: String) -> (String, String)? {
        var words = line.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        var amount: [String] = []
        if let last = words.last, last.count <= 3, !last.contains(where: \.isNumber), words.count >= 3 {
            amount.insert(words.removeLast(), at: 0)
        }
        guard let number = words.last, number.first(where: { $0.isNumber || "$€£¥".contains($0) }) != nil,
              !number.contains("/"), !number.contains(":"), number.contains(where: \.isNumber)
        else { return nil }
        amount.insert(words.removeLast(), at: 0)
        if let code = words.last, currencyCodes.contains(code.uppercased()), words.count >= 2 {
            amount.insert(words.removeLast(), at: 0)
        }
        guard !words.isEmpty else { return nil }
        return (words.joined(separator: " "), amount.joined(separator: " "))
    }

    private static let currencyCodes: Set<String> = ["EUR", "USD", "GBP", "RWF", "FRW", "KES", "JPY"]
}
#endif
