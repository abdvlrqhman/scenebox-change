//
//  Profile.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import Foundation
import SwiftUI

nonisolated struct Profile: Identifiable, Codable, Sendable, Hashable {
    static let maxPerAccount = 5
    static let maxNameLength = 24
    /// Id of the profile created by the old guest mode.
    static let guestID = "guest"

    let id: String
    var name: String
    var colorIndex: Int
    var avatarURLString: String?
    var createdAt: Date

    /// Photos are stored as a file name inside `ProfileFiles.avatars`; the
    /// absolute path is rebuilt each time because the app container moves.
    var avatarURL: URL? {
        guard let avatarURLString, !avatarURLString.isEmpty else { return nil }
        if avatarURLString.contains("://") { return URL(string: avatarURLString) }
        return ProfileFiles.avatars.appendingPathComponent(avatarURLString)
    }
    var hasPhoto: Bool { avatarURLString != nil }

    static let colors: [Color] = [
        Color(red: 0.91, green: 0.27, blue: 0.27),   // red
        Color(red: 0.18, green: 0.56, blue: 0.93),   // blue
        Color(red: 0.22, green: 0.72, blue: 0.45),   // green
        Color(red: 0.95, green: 0.62, blue: 0.14),   // amber
    ]

    var color: Color { Self.colors[colorIndex % Self.colors.count] }

    var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}
