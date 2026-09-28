#!/usr/bin/env swift
//
// Writes Keaser's app icon, the Keaser mark in white on black, as an Icon
// Composer document: Keaser/Resources/AppIcon.icon, which Xcode compiles.
//
// The icon is generated rather than drawn by hand so it can be regenerated
// instead of being a mystery file in the project. `KeaserMark` in
// Keaser/Design/KeaserLogo.swift draws the same shape from the same numbers
// (see `Mark` below); change both together.
//
// The mark is a white rounded tile with a "K" cut out of it, drawn with round
// strokes of one weight: a stem, an arm rising from it, and a leg that
// springs from the arm rather than the stem. That junction is what makes it
// Keaser's K rather than a typeface's, and it stays legible down to the small
// sizes used in Settings and notifications.
//
// The document is built the way Icon Composer builds one, so iOS 26 and later
// can draw it in Liquid Glass on every home screen style:
//
// - The black background is the document's fill, not a layer. A dark
//   specialization keeps it black in dark mode too (left alone, the system
//   swaps in its own dark grey), so the icon is the same in both.
// - The mark is the only layer, an SVG, in one group with glass on. The
//   system lights its edges, the cut-out K's included, and casts its shadow.
// - Clear and tinted need nothing of their own: the system draws the white
//   tile in the tint (or clear glass) and the K shows the dark glass beneath.
//
// iOS 18 to 25 get flat icons (default, dark and tinted) that Xcode renders
// from this document at build time. Xcode ignores an AppIcon.appiconset once
// an AppIcon.icon exists, so there is no PNG to keep in step.
//
//   swift scripts/make_icon.swift                # AppIcon.icon + docs/app-icon.png
//   swift scripts/make_icon.swift --previews DIR # also every appearance in DIR
//
// Open the document in Icon Composer (Xcode > Open Developer Tool) to preview
// it; change the numbers here rather than saving over it from there.
//
import CoreGraphics
import Foundation
import SwiftUI

/// Icon Composer's canvas for iPhone, in points.
let canvas = 1024.0
/// The tile's share of the icon. Leaves the black margin the brief asks for
/// while staying legible on the home screen.
let tileFraction = 0.6

/// Fractions of the tile's side. Mirrors `KeaserMark` in the app.
enum Mark {
    static let cornerRadius = 0.27
    static let stroke = 0.14
    static let stemOrigin = CGPoint(x: 0.245, y: 0.235)
    static let stemHeight = 0.53
    static let armStart = CGPoint(x: 0.33, y: 0.575)
    static let armEnd = CGPoint(x: 0.70, y: 0.265)
    static let legStart = CGPoint(x: 0.49, y: 0.44)
    static let legEnd = CGPoint(x: 0.70, y: 0.735)

    static func path(in rect: CGRect) -> CGPath {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * s, y: origin.y + p.y * s) }
        let tile = RoundedRectangle(cornerRadius: cornerRadius * s, style: .continuous)
            .path(in: CGRect(origin: origin, size: CGSize(width: s, height: s)))
            .cgPath
        let width = stroke * s
        let stem = CGPath(
            roundedRect: CGRect(origin: point(stemOrigin), size: CGSize(width: width, height: stemHeight * s)),
            cornerWidth: width / 2, cornerHeight: width / 2, transform: nil
        )
        let strokes = CGMutablePath()
        strokes.move(to: point(armStart))
        strokes.addLine(to: point(armEnd))
        strokes.move(to: point(legStart))
        strokes.addLine(to: point(legEnd))
        let arms = strokes.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return tile.subtracting(stem.union(arms))
    }
}

/// The mark as an SVG: the tile fills a canvas-sized view box, so the
/// layer's scale in icon.json is the tile's share of the icon. The numbers
/// are top-down, like SwiftUI and SVG, so nothing is flipped.
func markSVG() -> String {
    func number(_ value: CGFloat) -> String {
        var text = String(format: "%.2f", Double(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
    func point(_ p: CGPoint) -> String { "\(number(p.x)) \(number(p.y))" }

    var data = ""
    Mark.path(in: CGRect(x: 0, y: 0, width: canvas, height: canvas)).applyWithBlock { element in
        let p = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: data += "M\(point(p[0]))"
        case .addLineToPoint: data += "L\(point(p[0]))"
        case .addQuadCurveToPoint: data += "Q\(point(p[0])) \(point(p[1]))"
        case .addCurveToPoint: data += "C\(point(p[0])) \(point(p[1])) \(point(p[2]))"
        case .closeSubpath: data += "Z"
        @unknown default: fatalError("Unknown path element")
        }
    }
    let side = Int(canvas)
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(side)" height="\(side)" viewBox="0 0 \(side) \(side)">
      <path fill="#FFFFFF" fill-rule="evenodd" d="\(data)"/>
    </svg>

    """
}

/// icon.json, in Icon Composer's format.
func iconJSON() throws -> Data {
    // Written as the shortest decimal ("0.6"), as Icon Composer writes them,
    // not a double's full expansion.
    func decimal(_ value: Double) -> NSDecimalNumber { NSDecimalNumber(string: String(value)) }
    let black = ["solid": "srgb:0.00000,0.00000,0.00000,1.00000"]
    let layer: [String: Any] = [
        "blend-mode": "normal",
        "glass": true,
        "image-name": "Mark.svg",
        "name": "Mark",
        "position": ["scale": decimal(tileFraction), "translation-in-points": [0, 0]] as [String: Any],
    ]
    let group: [String: Any] = [
        "layers": [layer],
        "shadow": ["kind": "neutral", "opacity": decimal(0.6)] as [String: Any],
        "translucency": ["enabled": true, "value": decimal(0.2)] as [String: Any],
    ]
    let document: [String: Any] = [
        "fill-specializations": [
            ["value": black],
            ["appearance": "dark", "value": black],
        ],
        "groups": [group],
        "supported-platforms": ["squares": ["iOS"]],
    ]
    var data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    data.append(contentsOf: Array("\n".utf8))
    return data
}

func writeIcon(to bundle: URL) throws {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: bundle)
    try fileManager.createDirectory(at: bundle.appending(path: "Assets"), withIntermediateDirectories: true)
    try iconJSON().write(to: bundle.appending(path: "icon.json"))
    try Data(markSVG().utf8).write(to: bundle.appending(path: "Assets/Mark.svg"))
}

/// Icon Composer's command line renderer, which draws the icon as iOS does.
func ictool() throws -> URL {
    let select = Process()
    select.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    select.arguments = ["-p"]
    let pipe = Pipe()
    select.standardOutput = pipe
    try select.run()
    select.waitUntilExit()
    let developer = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let tool = URL(fileURLWithPath: developer)
        .deletingLastPathComponent()
        .appending(path: "Applications/Icon Composer.app/Contents/Executables/ictool")
    guard FileManager.default.isExecutableFile(atPath: tool.path) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: tool.path])
    }
    return tool
}

/// Renders one appearance (Default, Dark, ClearLight, ClearDark, TintedLight
/// or TintedDark) at twice `points`.
func render(_ bundle: URL, rendition: String, points: Int, to output: URL) throws {
    let process = Process()
    process.executableURL = try ictool()
    process.arguments = [
        bundle.path, "--export-image", "--output-file", output.path,
        "--platform", "iOS", "--rendition", rendition,
        "--width", "\(points)", "--height", "\(points)", "--scale", "2",
    ]
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: output.path])
    }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = root.appending(path: "Keaser/Resources/AppIcon.icon")
try writeIcon(to: bundle)
print("Wrote \(bundle.path)")

// The README's picture of the icon, drawn as iOS draws it.
let picture = root.appending(path: "docs/app-icon.png")
try render(bundle, rendition: "Default", points: 120, to: picture)
print("Wrote \(picture.path)")

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--previews"), arguments.indices.contains(flag + 1) {
    let directory = URL(fileURLWithPath: arguments[flag + 1])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for rendition in ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"] {
        let output = directory.appending(path: "AppIcon-\(rendition).png")
        try render(bundle, rendition: rendition, points: 512, to: output)
        print("Wrote \(output.path)")
    }
}
