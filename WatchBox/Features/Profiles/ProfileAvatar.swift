//
//  ProfileAvatar.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import SwiftUI
import Kingfisher
import UIKit

struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 96
    var preview: UIImage? = nil

    var body: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview).resizable().scaledToFill()
            } else if let url = profile.avatarURL {
                KFImage(url)
                    .setProcessor(DownsamplingImageProcessor(size: CGSize(width: 512, height: 512)))
                    .cacheOriginalImage()
                    .placeholder { monogram }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var monogram: some View {
        ZStack {
            profile.color
            Text(profile.initial)
                .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
