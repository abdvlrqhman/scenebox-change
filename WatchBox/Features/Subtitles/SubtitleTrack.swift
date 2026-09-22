//
//  SubtitleTrack.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation

nonisolated struct SubtitleTrack: Identifiable, Sendable, Hashable {
    let id: String
    let languageCode: String   // ISO 639-2, e.g. "eng"
    let url: URL
    var fileName: String? = nil    // original file / release name, used to match the release
    var encoding: String? = nil    // code page the uploader declared
    var fps: Double? = nil         // frame rate of the release it was timed against

    var languageName: String { SubtitleLanguage.displayName(for: languageCode) }
}
