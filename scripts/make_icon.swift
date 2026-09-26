#!/usr/bin/env swift
//
// Draws Keaser's app icon: the Keaser mark in white on black.
//
// The icon is generated rather than drawn by hand so it can be regenerated
// instead of being a mystery PNG in the asset catalogue. `KeaserMark` in
// Keaser/Design/KeaserLogo.swift draws the same shape from the same numbers
// (see `Mark` below); change both together.
//
// The mark is a white rounded tile with a "K" cut out of it, drawn with round
// strokes of one weight: a stem, an arm rising from it, and a leg that
// springs from the arm rather than the stem. That junction is what makes it
// Keaser's K rather than a typeface's, and it stays legible down to the small
// sizes used in Settings and notifications.
//
//   swift scripts/make_icon.swift [output.png]
//
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let side = 1024.0
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

/// Written with no alpha channel at all: App Store validation rejects a
/// primary icon that carries one, even when every pixel is opaque.
func drawIcon(to url: URL) throws {
    guard let context = CGContext(
        data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }

    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    let tile = side * tileFraction
    let rect = CGRect(x: (side - tile) / 2, y: (side - tile) / 2, width: tile, height: tile)
    // The mark's numbers are top-down, like SwiftUI; CoreGraphics counts up
    // from the bottom, so flip before drawing.
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)
    context.addPath(Mark.path(in: rect))
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fillPath(using: .evenOdd)

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appending(path: "Keaser/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try drawIcon(to: output)
print("Wrote \(output.path)")
