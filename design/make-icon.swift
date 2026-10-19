// Uygulama ikonunu çizer: swift design/make-icon.swift <çıktı.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func capsule(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
}

// macOS ikon ızgarası: 824 pt gövde, 100 pt kenar boşluğu.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Gölge
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(squircle); ctx.setFillColor(color(0x000000)); ctx.fillPath()
ctx.restoreGState()

// Arka plan degradesi
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [color(0x7C5CFF), color(0x4F46E5), color(0x1E1B4B)] as CFArray,
                    locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 250, y: 924), end: CGPoint(x: 780, y: 100),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Üstten yumuşak ışık
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])

// Çentikten sarkan panel: üst kenara yapışık, içbükey kulaklı, alt köşeleri yuvarlak.
let panelW: CGFloat = 580, panelH: CGFloat = 430, ear: CGFloat = 44, bottomR: CGFloat = 100
let left = 512 - panelW / 2, right = 512 + panelW / 2, top: CGFloat = 924, bottom = top - panelH
let panel = CGMutablePath()
panel.move(to: CGPoint(x: left - ear, y: top))
panel.addQuadCurve(to: CGPoint(x: left, y: top - ear), control: CGPoint(x: left, y: top))
panel.addLine(to: CGPoint(x: left, y: bottom + bottomR))
panel.addQuadCurve(to: CGPoint(x: left + bottomR, y: bottom), control: CGPoint(x: left, y: bottom))
panel.addLine(to: CGPoint(x: right - bottomR, y: bottom))
panel.addQuadCurve(to: CGPoint(x: right, y: bottom + bottomR), control: CGPoint(x: right, y: bottom))
panel.addLine(to: CGPoint(x: right, y: top - ear))
panel.addQuadCurve(to: CGPoint(x: right + ear, y: top), control: CGPoint(x: right, y: top))
panel.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x0B0820, 0.55))
ctx.addPath(panel); ctx.setFillColor(color(0x07070C)); ctx.fillPath()
ctx.restoreGState()
// Panelin ince kenar parlaması
ctx.addPath(panel); ctx.setStrokeColor(color(0xFFFFFF, 0.08)); ctx.setLineWidth(3); ctx.strokePath()

// Canlı göstergesi + ses dalgası, ortada
let waves: [CGFloat] = [18, 34, 52, 34, 18]
let waveW: CGFloat = 11, gap: CGFloat = 11, dotSize: CGFloat = 30
let groupW = dotSize + 26 + CGFloat(waves.count) * waveW + CGFloat(waves.count - 1) * gap
let groupX = 512 - groupW / 2, groupY = top - 120
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 22, color: color(0xFF3B5C, 0.9))
ctx.setFillColor(color(0xFF3B5C))
ctx.fillEllipse(in: CGRect(x: groupX, y: groupY - dotSize / 2, width: dotSize, height: dotSize))
ctx.restoreGState()
for (i, h) in waves.enumerated() {
    let x = groupX + dotSize + 26 + CGFloat(i) * (waveW + gap)
    ctx.addPath(capsule(CGRect(x: x, y: groupY - h / 2, width: waveW, height: h)))
    ctx.setFillColor(color(0xFFFFFF, 0.6)); ctx.fillPath()
}

// Altyazı satırları (ortalı): çeviri parlak degrade, asıl metin soluk
let accent = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(0x5EEAD4), color(0x60A5FA), color(0xC084FC)] as CFArray,
                        locations: [0, 0.5, 1])!
func centeredLine(widths: [CGFloat], y: CGFloat, height: CGFloat, fill: (CGRect) -> Void) {
    let spacing: CGFloat = 18
    let total = widths.reduce(0, +) + spacing * CGFloat(widths.count - 1)
    var x = 512 - total / 2
    for w in widths {
        fill(CGRect(x: x, y: y, width: w, height: height))
        x += w + spacing
    }
}
let barH: CGFloat = 46
for (widths, y) in [([170, 250], bottom + 228), ([300], bottom + 160)] as [([CGFloat], CGFloat)] {
    centeredLine(widths: widths, y: y, height: barH) { rect in
        ctx.saveGState()
        ctx.addPath(capsule(rect)); ctx.clip()
        ctx.drawLinearGradient(accent, start: CGPoint(x: 512 - 230, y: 0), end: CGPoint(x: 512 + 230, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
}
centeredLine(widths: [130, 200], y: bottom + 86, height: 30) { rect in
    ctx.addPath(capsule(rect)); ctx.setFillColor(color(0xFFFFFF, 0.3)); ctx.fillPath()
}
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("✓", out)
