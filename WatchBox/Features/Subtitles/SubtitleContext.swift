//
//  SubtitleContext.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

nonisolated struct SubtitleContext: Sendable, Equatable {
    let imdbID: String
    let type: MediaType
    let season: Int?
    let episode: Int?
    /// Name of the release being played, to pick subtitles timed for it.
    var releaseName: String? = nil

    /// The source (release) being played; subtitle choices are saved per source.
    var sourceKey: String? = nil

    func withSource(_ key: String?) -> SubtitleContext {
        guard let key else { return self }
        var copy = self
        copy.sourceKey = key
        return copy
    }

    func withRelease(_ name: String?) -> SubtitleContext {
        guard let name, !name.isEmpty else { return self }
        var copy = self
        copy.releaseName = name
        return copy
    }
}
