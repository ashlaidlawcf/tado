// Renders the app icon ("tado°" wordmark on tado yellow-orange) and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [output-dir]
import AppKit
import CoreText

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(size px: Int) -> Data {
    let s = CGFloat(px) / 1024   // draw in 1024-point space, scaled
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt rounded square centred on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(color(0xFFA515))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient (tado yellow-orange)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [color(0xFFBB33), color(0xFF9F0A)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // subtle top highlight
    let highlight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                               colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray,
                               locations: [0, 1])!
    ctx.drawLinearGradient(highlight, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    ctx.restoreGState()

    // Wordmark
    let ink = color(0x1E1E1E)
    let font = CTFontCreateWithName("AvenirNext-Medium" as CFString, 250, nil)
    let attributed = NSAttributedString(string: "tado", attributes: [
        .font: font, .foregroundColor: ink, .kern: -14,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let glyphBounds = CTLineGetImageBounds(line, ctx)

    let ringRadius: CGFloat = 23
    let ringStroke: CGFloat = 9
    let ringGap: CGFloat = 2
    let totalWidth = glyphBounds.width + ringGap + ringRadius * 2 + ringStroke

    // Centre optically on the letters' x-height/ascender box; ring sits level with the ascenders.
    let originX = 512 - totalWidth / 2 - glyphBounds.minX
    let originY = 512 - glyphBounds.height / 2 - glyphBounds.minY
    ctx.textPosition = CGPoint(x: originX, y: originY)
    CTLineDraw(line, ctx)

    let ringCenter = CGPoint(x: originX + glyphBounds.maxX + ringGap + ringRadius + ringStroke / 2,
                             y: originY + glyphBounds.maxY - ringRadius - ringStroke / 2)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(ringStroke)
    ctx.strokeEllipse(in: CGRect(x: ringCenter.x - ringRadius, y: ringCenter.y - ringRadius,
                                 width: ringRadius * 2, height: ringRadius * 2))

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: outDir.appending(path: "AppIcon-preview.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outDir.appending(path: "AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(outDir.path)/AppIcon.icns" : "iconutil failed")
