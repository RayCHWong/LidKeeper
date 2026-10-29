import CoreGraphics
import Foundation
import ImageIO
import LidKeeperArt

// Renders LidKeeper's app icon into an .iconset folder, at every size macOS
// asks for. Scripts/make-app.sh turns the folder into AppIcon.icns with
// `iconutil`.
//
// Usage:  make-icon OUTPUT.iconset

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon OUTPUT.iconset\n".utf8))
    exit(64)
}

let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

// iconutil wants each size at 1x and 2x.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = points * scale
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { exit(1) }
        Logo.drawAppIcon(in: ctx, side: CGFloat(side))

        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let url = folder.appendingPathComponent(name) as CFURL
        guard let image = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)
        else { exit(1) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
    }
}
