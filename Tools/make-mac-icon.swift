import SwiftUI
import AppKit

// macOS app icons are drawn, not masked, by the system: the artwork itself has
// to carry the squircle and the shadow. Apple's grid puts an 824pt rounded
// square on a 1024pt canvas, nudged up slightly so the shadow has room below.
let canvas: CGFloat = 1024
let content: CGFloat = 824
let radius: CGFloat = 185.4

let srcPath = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
guard let src = NSImage(contentsOfFile: srcPath) else { fatalError("no source image") }

struct MacIcon: View {
    let image: NSImage
    var body: some View {
        ZStack {
            Color.clear
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: content, height: content)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 10)
                .offset(y: -8)
        }
        .frame(width: canvas, height: canvas)
    }
}

@MainActor func render() -> CGImage {
let renderer = ImageRenderer(content: MacIcon(image: src))
renderer.scale = 1
guard let m = renderer.cgImage else { fatalError("render failed") }
return m
}
let master = MainActor.assumeIsolated { render() }

// One master render, downsampled per slot — resampling the 1024 keeps the
// squircle's curvature consistent instead of re-rasterising the shape small.
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let out = ctx.makeImage() else { fatalError() }
    let rep = NSBitmapImageRep(cgImage: out)
    rep.size = NSSize(width: px, height: px)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError() }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-mac-\(px).png"))
    print("wrote \(px)")
}

// Usage:
//   swift Tools/make-mac-icon.swift \
//     bigyap/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png \
//     bigyap/Assets.xcassets/AppIcon.appiconset
