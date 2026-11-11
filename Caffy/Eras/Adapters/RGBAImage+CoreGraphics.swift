import CoreGraphics
import Foundation

extension RGBAImage {
    /// `image` scaled to fill a `side × side` square (cropping the longer
    /// edge, like a collage print) and converted to sRGB bytes with straight
    /// alpha. Wide-colour photos are brought into sRGB on the way.
    nonisolated init?(_ image: CGImage, side: Int) {
        guard side > 0, image.width > 0, image.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let scale = max(Double(side) / Double(image.width), Double(side) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2, width: width, height: height))

        guard let data = context.data else { return nil }
        var bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side * 4))
        // Core Graphics stores colours multiplied by alpha; undo that.
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[offset + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 {
                bytes[offset + channel] = UInt8(min(255, Int(bytes[offset + channel]) * 255 / alpha))
            }
        }
        self.init(width: side, height: side, bytes: bytes)
    }
}
