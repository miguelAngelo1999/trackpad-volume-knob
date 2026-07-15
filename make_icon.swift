#!/usr/bin/env swift
// Renders a high-quality app icon for TrackpadVolumeKnob.
// Produces icon.png at the requested size.
// Usage: swift make_icon.swift <size> <output_path>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
let size = CGFloat(Double(args[1])!)
let output = args[2]

// Canvas
let colorSpace = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil,
    width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let corner = size * 0.225   // macOS icon corner radius ratio

// ── Background: deep navy-to-purple radial gradient ──────────────────────────
let gradColors = [
    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.22, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.16, green: 0.05, blue: 0.32, alpha: 1).cgColor
]
let locations: [CGFloat] = [0, 1]
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradColors as CFArray,
    locations: locations
)!

// Rounded rect clip
let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(path)
ctx.clip()

ctx.drawRadialGradient(
    gradient,
    startCenter: CGPoint(x: size * 0.38, y: size * 0.62),
    startRadius: 0,
    endCenter: CGPoint(x: size * 0.5, y: size * 0.5),
    endRadius: size * 0.75,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// ── Subtle inner glow ring ────────────────────────────────────────────────────
let glowColors = [
    NSColor(white: 1, alpha: 0.07).cgColor,
    NSColor(white: 1, alpha: 0.0).cgColor
]
let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(
    glowGrad,
    startCenter: CGPoint(x: size * 0.5, y: size * 0.5), startRadius: size * 0.1,
    endCenter:   CGPoint(x: size * 0.5, y: size * 0.5), endRadius: size * 0.52,
    options: []
)

// ── Knob ring track ───────────────────────────────────────────────────────────
let trackLineWidth = size * 0.045
let trackRadius    = size * 0.34
let trackCenter    = CGPoint(x: size * 0.5, y: size * 0.5)
ctx.setLineWidth(trackLineWidth)
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor)
ctx.strokeEllipse(in: CGRect(
    x: trackCenter.x - trackRadius,
    y: trackCenter.y - trackRadius,
    width: trackRadius * 2,
    height: trackRadius * 2
))

// ── Knob arc (270° sweep, clockwise from top-left) ───────────────────────────
let arcPath = CGMutablePath()
arcPath.addArc(
    center: trackCenter,
    radius: trackRadius,
    startAngle: .pi * 1.5,           // 12 o'clock
    endAngle:   .pi * 1.5 - .pi * 1.5, // 9 o'clock (270° CW = 75% fill)
    clockwise: true
)
// Gradient stroke along arc using a clipped approach
ctx.saveGState()
let arcStrokePath = arcPath.copy(strokingWithWidth: trackLineWidth,
                                  lineCap: .round,
                                  lineJoin: .miter,
                                  miterLimit: 10)
ctx.addPath(arcStrokePath)
ctx.clip()

let arcColors = [
    NSColor(calibratedRed: 0.45, green: 0.70, blue: 1.0, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.80, green: 0.50, blue: 1.0, alpha: 1).cgColor
]
let arcGrad = CGGradient(colorsSpace: colorSpace, colors: arcColors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
    arcGrad,
    start: CGPoint(x: size * 0.2, y: size * 0.8),
    end:   CGPoint(x: size * 0.8, y: size * 0.2),
    options: []
)
ctx.restoreGState()

// ── Speaker wave SF Symbol ────────────────────────────────────────────────────
let symSize = size * 0.30
let symConfig = NSImage.SymbolConfiguration(pointSize: symSize, weight: .medium)
if let sym = NSImage(systemSymbolName: "speaker.wave.2.fill",
                     accessibilityDescription: nil)?
            .withSymbolConfiguration(symConfig) {

    // White tint
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    NSColor.white.setFill()
    let symRect = NSRect(origin: .zero, size: sym.size)
    symRect.fill()
    sym.draw(in: symRect, from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()

    // Centre it
    let imgW = tinted.size.width
    let imgH = tinted.size.height
    let imgX = (size - imgW) / 2
    let imgY = (size - imgH) / 2 - size * 0.01

    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    tinted.draw(in: NSRect(x: imgX, y: imgY, width: imgW, height: imgH))
}

// ── Fingerprint / touch indicator dots at bottom ─────────────────────────────
let dotRadius = size * 0.025
let dotY      = size * 0.175
let dotSpacing = size * 0.075
let dotCount  = 3
for i in 0..<dotCount {
    let dotX = size * 0.5 + CGFloat(i - dotCount/2) * dotSpacing
    ctx.setFillColor(NSColor(white: 1, alpha: 0.45).cgColor)
    ctx.fillEllipse(in: CGRect(x: dotX - dotRadius, y: dotY - dotRadius,
                               width: dotRadius*2, height: dotRadius*2))
}

// ── Output ────────────────────────────────────────────────────────────────────
let cgImage = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: output) as CFURL,
    "public.png" as CFString, 1, nil
)!
CGImageDestinationAddImage(dest, cgImage, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(Int(size))×\(Int(size)) → \(output)")
