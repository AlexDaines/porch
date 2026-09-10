// Deterministic, original vector monogram rendered without creating any window.
// Run: swift tools/generate-icon.swift /absolute/path/to/icon.png
import AppKit

let size = NSSize(width: 1024, height: 1024)
let pixels = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let context = NSGraphicsContext(cgContext: pixels, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.black.setFill()
NSRect(origin: .zero, size: size).fill()
let bone = NSColor(srgbRed: 233 / 255, green: 228 / 255, blue: 214 / 255, alpha: 1)
let font = NSFont(name: "Menlo-Bold", size: 760) ?? NSFont.monospacedSystemFont(ofSize: 760, weight: .bold)
("P" as NSString).draw(at: NSPoint(x: 260, y: 60), withAttributes: [.font: font, .foregroundColor: bone])
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: pixels.makeImage()!)
let data = bitmap.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
