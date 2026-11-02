// Renders the 04 · Log mark on the Default dark base into the 1024pt app icon.
//   swift Tools/MakeIcon.swift Tasks/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func c(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
// Ground: the base with a faint lift toward the top, as the window's own surface.
let grad = CGGradient(colorsSpace: cs, colors: [c(0x242424), c(0x1A1A1A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// The mark's viewBox is 150 150 724 724; draw it 640pt wide, centred, y flipped for Core Graphics.
let markSize: CGFloat = 640
let s = markSize / 724
let ox = (size - markSize) / 2, oy = (size - markSize) / 2
func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: ox + (x - 150) * s, y: size - (oy + (y - 150 + h) * s), width: w * s, height: h * s)
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + (x - 150) * s, y: size - (oy + (y - 150) * s)) }
func round(_ rect: CGRect, _ rad: CGFloat, _ col: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rad * s, cornerHeight: rad * s, transform: nil)); ctx.setFillColor(col); ctx.fillPath()
}
func circle(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, _ col: CGColor) {
    ctx.setFillColor(col); ctx.fillEllipse(in: r(cx - rad, cy - rad, rad * 2, rad * 2))
}
let trail = c(0x6D7072), rings = c(0xA8ADB1), bar = c(0xE6EDF3), head = c(0x2F81F7)
ctx.setFillColor(trail); ctx.fill(r(304, 436, 36, 64)); ctx.fill(r(304, 612, 36, 64))
round(r(462, 524, 280, 64), 32, trail)
round(r(462, 700, 220, 64), 32, trail)
circle(322, 556, 56, rings); circle(322, 732, 56, rings)
round(r(462, 296, 340, 80), 40, bar)
// The head, with the check cut out of it.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
circle(322, 336, 100, head)
ctx.setBlendMode(.clear)
ctx.setLineWidth(30 * s); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: pt(276.5, 339.5)); ctx.addLine(to: pt(308, 371)); ctx.addLine(to: pt(367.5, 304.5)); ctx.strokePath()
ctx.setBlendMode(.normal)
ctx.endTransparencyLayer()
// The cut shows the ground through it; on the icon, fill it with the ground's colour so the PNG stays opaque.
let img = ctx.makeImage()!
let flat = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
flat.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, flat.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
