// Renders the Noti AI app icon. Usage: swift make-icon.swift <out-dir>
// Produces icon_1024.png and AppIcon.icns (via iconutil).
import AppKit

let ink1 = NSColor(srgbRed: 0x24/255, green: 0x34/255, blue: 0x5E/255, alpha: 1)
let ink2 = NSColor(srgbRed: 0x14/255, green: 0x1D/255, blue: 0x38/255, alpha: 1)
let inkText = NSColor(srgbRed: 0x1B/255, green: 0x27/255, blue: 0x47/255, alpha: 1)
let marker = NSColor(srgbRed: 1.0, green: 0xD8/255, blue: 0x4D/255, alpha: 1)
let paper = NSColor(srgbRed: 0xF7/255, green: 0xF8/255, blue: 0xFA/255, alpha: 1)

func render(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)

    // Body: macOS icon grid, 824pt rounded tile centred in 1024 with room for shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                  color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.addPath(tile); ctx.setFillColor(paper.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let top = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    let bottom = NSColor(srgbRed: 0xEC/255, green: 0xEE/255, blue: 0xF3/255, alpha: 1)
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
        let r = CGRect(x: x, y: y, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.setFillColor(c.cgColor); ctx.fillPath()
    }
    // Quiet lines of text.
    let faint = NSColor(srgbRed: 0xCB/255, green: 0xD0/255, blue: 0xDB/255, alpha: 1)
    bar(214, 512, 470, 38, faint)
    bar(214, 260, 360, 38, faint)

    // The highlighted line: a chisel-tip marker stroke with one ink line on it.
    let swash = CGMutablePath()
    swash.move(to: CGPoint(x: 196, y: 350))
    swash.addCurve(to: CGPoint(x: 826, y: 360), control1: CGPoint(x: 420, y: 343), control2: CGPoint(x: 630, y: 348))
    swash.addLine(to: CGPoint(x: 804, y: 456))
    swash.addCurve(to: CGPoint(x: 174, y: 450), control1: CGPoint(x: 600, y: 462), control2: CGPoint(x: 380, y: 456))
    swash.closeSubpath()
    ctx.addPath(swash); ctx.setFillColor(marker.cgColor); ctx.fillPath()
    bar(220, 384, 540, 40, inkText)
    ctx.restoreGState()

    // Hairline edge so the white tile holds its shape on white backgrounds.
    ctx.addPath(tile); ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.06).cgColor)
    ctx.setLineWidth(3); ctx.strokePath()

    // The reply: a small ink notification card at the top right.
    let card = CGRect(x: 486, y: 636, width: 360, height: 156)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30,
                  color: NSColor(srgbRed: 0x1B/255, green: 0x27/255, blue: 0x47/255, alpha: 0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 46, cornerHeight: 46, transform: nil))
    ctx.setFillColor(inkText.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.setFillColor(marker.cgColor)
    ctx.fillEllipse(in: CGRect(x: 522, y: 680, width: 68, height: 68))
    bar(614, 726, 196, 26, paper.withAlphaComponent(0.92))
    bar(614, 678, 128, 26, paper.withAlphaComponent(0.4))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(1024).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_1024.png"))
try! render(64).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_64.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("ok")
