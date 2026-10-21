//
//  OpaqueBounds.swift
//  SceneBox
//

import CoreGraphics
import Foundation

nonisolated enum OpaqueBounds {
    /// The smallest pixel rectangle (rows from the top) holding every pixel
    /// whose alpha is above `threshold`; nil when the image is see-through.
    /// `alpha` holds `components` bytes per pixel, alpha at `offset`.
    static func rect(alpha: [UInt8], width: Int, height: Int, components: Int = 1, offset: Int = 0,
                     threshold: UInt8 = 10) -> CGRect? {
        guard width > 0, height > 0, alpha.count >= width * height * components else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[(row + x) * components + offset] > threshold {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let boxWidth: Int = maxX - minX + 1
        let boxHeight: Int = maxY - minY + 1
        return CGRect(x: minX, y: minY, width: boxWidth, height: boxHeight)
    }
}
