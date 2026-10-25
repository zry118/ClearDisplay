// makeicon — 生成 ClearDisplay 的应用图标
//
// 设计意图：左边糊、右边清晰，一眼看懂产品是干什么的。
// 背景用蓝紫渐变，中间一台显示器，屏幕里的点阵左半边做了模糊处理。
//
// 编译运行：
//   swiftc -O makeicon.swift -o makeicon && ./makeicon

import AppKit
import CoreGraphics
import Foundation

let S: CGFloat = 1024
let outDir = "ClearDisplay.iconset"

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

func render(size: CGFloat) -> Data {
    let scale = size / S
    let w = Int(size), h = Int(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("无法创建绘图上下文")
    }
    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // ---- 底板：macOS 圆角矩形 ----
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius: CGFloat = 186
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [color(0x3B82F6), color(0x7C3AED)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])
    // 顶部柔光
    let shine = CGGradient(colorsSpace: cs,
                           colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
                                    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(shine,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.midY + 60),
                           options: [])
    ctx.restoreGState()

    // ---- 显示器 ----
    let mw: CGFloat = 560, mh: CGFloat = 380
    let mx = (S - mw) / 2, my = S / 2 - mh / 2 + 34
    let screen = CGRect(x: mx, y: my, width: mw, height: mh)
    let sr = CGPath(roundedRect: screen, cornerWidth: 42, cornerHeight: 42, transform: nil)

    ctx.addPath(sr)
    ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.07, blue: 0.13, alpha: 0.92))
    ctx.fillPath()
    ctx.addPath(sr)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.setLineWidth(14)
    ctx.strokePath()

    // 支架
    let neck = CGRect(x: S / 2 - 34, y: my - 62, width: 68, height: 64)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.fill(neck)
    let base = CGPath(roundedRect: CGRect(x: S / 2 - 130, y: my - 92, width: 260, height: 34),
                      cornerWidth: 17, cornerHeight: 17, transform: nil)
    ctx.addPath(base)
    ctx.fillPath()

    // ---- 屏幕内容：左糊右清 ----
    let cols = 7, rows = 4
    let padX: CGFloat = 66, padY: CGFloat = 54
    let cellW = (mw - padX * 2) / CGFloat(cols)
    let cellH = (mh - padY * 2) / CGFloat(rows)
    let dot: CGFloat = 34
    let splitX = screen.midX

    for r in 0..<rows {
        for c in 0..<cols {
            let cx = screen.minX + padX + cellW * (CGFloat(c) + 0.5)
            let cy = screen.minY + padY + cellH * (CGFloat(r) + 0.5)
            let box = CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot)
            let path = CGPath(roundedRect: box, cornerWidth: 9, cornerHeight: 9, transform: nil)

            if cx < splitX {
                // 模糊：多次偏移叠画，模拟失焦
                let offs: [(CGFloat, CGFloat)] = [
                    (0, 0), (-9, 0), (9, 0), (0, -9), (0, 9),
                    (-6, -6), (6, 6), (-6, 6), (6, -6),
                ]
                for (dx, dy) in offs {
                    ctx.saveGState()
                    ctx.translateBy(x: dx, y: dy)
                    ctx.addPath(path)
                    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
                    ctx.fillPath()
                    ctx.restoreGState()
                }
            } else {
                ctx.addPath(path)
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
                ctx.fillPath()
            }
        }
    }

    // 分界线
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
    ctx.setLineWidth(4)
    ctx.setLineDash(phase: 0, lengths: [14, 12])
    ctx.move(to: CGPoint(x: splitX, y: screen.minY + 34))
    ctx.addLine(to: CGPoint(x: splitX, y: screen.maxY - 34))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

// ---- 输出各尺寸 ----
try? FileManager.default.removeItem(atPath: outDir)
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants {
    let data = render(size: size)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("  \(name).png  \(Int(size))x\(Int(size))  \(data.count) 字节")
}
print("图标源文件已生成到 \(outDir)")
