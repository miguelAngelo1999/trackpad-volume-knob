#!/usr/bin/env swift
// Renders the app icon for Mac Trackpad Fix.
// A trackpad silhouette with two curved rotation arrows — clean and minimal.
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

// ── Background: dark charcoal gradient ───────────────────────────────────────
let gradColors = [
    NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.20, alpha: 1).cgColor
]
let locations: [CGFloat] = [0, 1]
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradColors as CFArray,
    locations: locations
)!

// Rounded rect clip
let bgPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// ── Trackpad shape (rounded rectangle, lighter) ──────────────────────────────
let padInset = size * 0.18
let padRect = CGRect(
    x: padInset,
    y: padInset - size * 0.02,
    width: size - padInset * 2,
    height: size - padInset * 2
)
let padCorner = size * 0.08
let padPath = CGPath(roundedRect: padRect, cornerWidth: padCorner, cornerHeight: padCorner, transform: nil)

// Subtle fill for the trackpad body
ctx.saveGState()
ctx.addPath(padPath)
ctx.setFillColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
ctx.fillPath()
ctx.restoreGState()

// Trackpad border
ctx.saveGState()
ctx.addPath(padPath)
ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.25).cgColor)
ctx.setLineWidth(size * 0.015)
ctx.strokePath()
ctx.restoreGState()

// ── Rotation arrows (two curved arrows forming a circle) ─────────────────────
let center = CGPoint(x: size * 0.5, y: size * 0.5 - size * 0.02)
let arrowRadius = size * 0.17
let arrowLineWidth = size * 0.028
let arrowHeadSize = size * 0.045

// Arc colors — a nice blue-to-teal gradient feel via two separate arcs
let topArcColor = NSColor(calibratedRed: 0.35, green: 0.75, blue: 1.0, alpha: 1.0).cgColor
let bottomArcColor = NSColor(calibratedRed: 0.35, green: 0.75, blue: 1.0, alpha: 0.7).cgColor

// Top arc (from ~30° to ~180°)
ctx.saveGState()
ctx.setStrokeColor(topArcColor)
ctx.setLineWidth(arrowLineWidth)
ctx.setLineCap(.round)

let topStart: CGFloat = .pi * 0.15
let topEnd: CGFloat = .pi * 0.85
ctx.addArc(center: center, radius: arrowRadius, startAngle: topStart, endAngle: topEnd, clockwise: false)
ctx.strokePath()

// Arrowhead at topEnd
let tipAngle1 = topEnd
let tipX1 = center.x + arrowRadius * cos(tipAngle1)
let tipY1 = center.y + arrowRadius * sin(tipAngle1)
let headAngle1a = tipAngle1 + .pi * 0.65
let headAngle1b = tipAngle1 + .pi * 1.35
ctx.setFillColor(topArcColor)
ctx.move(to: CGPoint(x: tipX1, y: tipY1))
ctx.addLine(to: CGPoint(x: tipX1 + arrowHeadSize * cos(headAngle1a),
                        y: tipY1 + arrowHeadSize * sin(headAngle1a)))
ctx.addLine(to: CGPoint(x: tipX1 + arrowHeadSize * cos(headAngle1b),
                        y: tipY1 + arrowHeadSize * sin(headAngle1b)))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// Bottom arc (from ~210° to ~360°)
ctx.saveGState()
ctx.setStrokeColor(bottomArcColor)
ctx.setLineWidth(arrowLineWidth)
ctx.setLineCap(.round)

let botStart: CGFloat = .pi * 1.15
let botEnd: CGFloat = .pi * 1.85
ctx.addArc(center: center, radius: arrowRadius, startAngle: botStart, endAngle: botEnd, clockwise: false)
ctx.strokePath()

// Arrowhead at botEnd
let tipAngle2 = botEnd
let tipX2 = center.x + arrowRadius * cos(tipAngle2)
let tipY2 = center.y + arrowRadius * sin(tipAngle2)
let headAngle2a = tipAngle2 + .pi * 0.65
let headAngle2b = tipAngle2 + .pi * 1.35
ctx.setFillColor(bottomArcColor)
ctx.move(to: CGPoint(x: tipX2, y: tipY2))
ctx.addLine(to: CGPoint(x: tipX2 + arrowHeadSize * cos(headAngle2a),
                        y: tipY2 + arrowHeadSize * sin(headAngle2a)))
ctx.addLine(to: CGPoint(x: tipX2 + arrowHeadSize * cos(headAngle2b),
                        y: tipY2 + arrowHeadSize * sin(headAngle2b)))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// ── Two finger dots (suggesting touch) ───────────────────────────────────────
let dotRadius = size * 0.022
let dot1 = CGPoint(x: center.x - size * 0.04, y: center.y + size * 0.01)
let dot2 = CGPoint(x: center.x + size * 0.04, y: center.y - size * 0.01)

ctx.setFillColor(NSColor(white: 1, alpha: 0.85).cgColor)
ctx.fillEllipse(in: CGRect(x: dot1.x - dotRadius, y: dot1.y - dotRadius,
                           width: dotRadius * 2, height: dotRadius * 2))
ctx.fillEllipse(in: CGRect(x: dot2.x - dotRadius, y: dot2.y - dotRadius,
                           width: dotRadius * 2, height: dotRadius * 2))

// ── Output ───────────────────────────────────────────────────────────────────
let cgImage = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: output) as CFURL,
    "public.png" as CFString, 1, nil
)!
CGImageDestinationAddImage(dest, cgImage, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(Int(size))×\(Int(size)) → \(output)")
