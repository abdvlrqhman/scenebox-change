//
//  AmbientBackdrop.swift
//  SceneBox
//

import SwiftUI
import Kingfisher

/// Light spilling from the artwork onto the black: a tiny, heavily blurred copy
/// of the image, saturated and faded out by its bottom edge. Static (no motion);
/// off when the viewer asks for less transparency.
struct AmbientBackdrop: View {
    let url: URL?
    var height: CGFloat = 560
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !reduceTransparency, let url {
            KFImage(url)
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 64, height: 64))
                              |> BlurImageProcessor(blurRadius: 24))
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipped()
                .saturation(1.5)
                .opacity(0.55)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
