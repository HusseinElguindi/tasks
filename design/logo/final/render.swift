// render.swift <in.svg> <out.png> <pixels>
import AppKit
let a = CommandLine.arguments
guard a.count == 4, let px = Int(a[3]), let img = NSImage(contentsOf: URL(fileURLWithPath: a[1])) else { fputs("usage/load failed\n", stderr); exit(1) }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
ctx.imageInterpolation = .high
NSGraphicsContext.current = ctx
img.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let srgb = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
try! srgb.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
