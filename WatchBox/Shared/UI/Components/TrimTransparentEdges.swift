//
//  TrimTransparentEdges.swift
//  SceneBox
//

import CoreGraphics
import Kingfisher
import UIKit

/// Cuts the see-through margins off title logos. Art sites centre logos on a
/// fixed canvas, which leaves narrow ones small and floating off the text's edge.
nonisolated struct TrimTransparentEdges: ImageProcessor {
    let identifier = "app.scenebox.trim-transparent-edges"

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
        switch item {
        case .image(let image):
            return Self.trimmed(image)
        case .data:
            return (DefaultImageProcessor.default |> self).process(item: item, options: options)
        }
    }

    private static func trimmed(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn,
              let bounds = OpaqueBounds.rect(alpha: pixels, width: width, height: height, components: 4, offset: 3),
              bounds.width < CGFloat(width) || bounds.height < CGFloat(height),
              let cropped = cgImage.cropping(to: bounds) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
