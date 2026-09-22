//
//  ProfileStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import Foundation
import Observation
import UIKit

/// Profiles live on this device: the list is a JSON file, photos are JPEGs next
/// to it, and each profile's watch history / watchlist has its own file.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private(set) var profiles: [Profile] = []
    private(set) var selected: Profile?
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    var errorMessage: String?

    private init() {
        load()
    }

    // MARK: Selection

    func select(_ profile: Profile) {
        selected = profile
        UserDefaults.standard.set(profile.id, forKey: Self.selectedKey)
    }

    func deselect() {
        selected = nil
        UserDefaults.standard.removeObject(forKey: Self.selectedKey)
    }

    // MARK: Mutations

    @discardableResult
    func create(name: String, colorIndex: Int? = nil) async -> Profile? {
        guard profiles.count < Profile.maxPerAccount else { return nil }
        let trimmed = Self.clean(name)
        guard !trimmed.isEmpty else { return nil }
        let profile = Profile(id: UUID().uuidString, name: trimmed,
                              colorIndex: colorIndex ?? Int.random(in: 0..<Profile.colors.count),
                              avatarURLString: nil, createdAt: Date())
        profiles.append(profile)
        persist()
        return profile
    }

    func rename(_ profile: Profile, to name: String) async {
        let trimmed = Self.clean(name)
        guard !trimmed.isEmpty, trimmed != profile.name else { return }
        var updated = current(profile); updated.name = trimmed
        save(updated)
    }

    func setColor(_ profile: Profile, index: Int) async {
        var updated = current(profile); updated.colorIndex = index
        save(updated)
    }

    func setPhoto(_ profile: Profile, image: UIImage) async {
        isWorking = true; defer { isWorking = false }
        guard let data = Self.avatarJPEG(from: image) else {
            errorMessage = "That image couldn't be used."
            return
        }
        // A fresh file name per photo, so image caches never show the old one.
        let fileName = "\(profile.id)-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try FileManager.default.createDirectory(at: ProfileFiles.avatars, withIntermediateDirectories: true)
            try data.write(to: ProfileFiles.avatars.appendingPathComponent(fileName), options: .atomic)
        } catch {
            errorMessage = "Couldn't save the photo. Please try again."
            return
        }
        var updated = current(profile)
        Self.deleteAvatarFile(of: updated)
        updated.avatarURLString = fileName
        save(updated)
    }

    func removePhoto(_ profile: Profile) async {
        var updated = current(profile)
        Self.deleteAvatarFile(of: updated)
        updated.avatarURLString = nil
        save(updated)
    }

    func delete(_ profile: Profile) async {
        Self.deleteAvatarFile(of: current(profile))
        for base in ProfileFiles.perProfileData {
            try? FileManager.default.removeItem(at: ProfileFiles.dataURL(base, profileID: profile.id))
        }
        profiles.removeAll { $0.id == profile.id }
        if selected?.id == profile.id { deselect() }
        persist()
    }

    // MARK: Persistence

    private static let selectedKey = "selectedProfileID"

    private func load() {
        var loaded = (try? Data(contentsOf: ProfileFiles.index))
            .flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        if loaded.isEmpty, let guest = Self.legacyGuest {
            loaded = [guest]            // guest-mode profile from before accounts were removed
        }
        profiles = loaded.sorted { $0.createdAt < $1.createdAt }
        if let id = UserDefaults.standard.string(forKey: Self.selectedKey) {
            selected = profiles.first { $0.id == id }
        }
        if selected == nil, profiles.count == 1 {
            selected = profiles[0]
        }
        hasLoaded = true
        if !loaded.isEmpty { persist() }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: ProfileFiles.directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: ProfileFiles.index, options: .atomic)
        } catch {
            errorMessage = "Couldn't save profiles. Please try again."
        }
    }

    private func save(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[i] = profile }
        if selected?.id == profile.id { selected = profile }
        persist()
    }

    private func current(_ profile: Profile) -> Profile {
        profiles.first { $0.id == profile.id } ?? profile
    }

    private static var legacyGuest: Profile? {
        UserDefaults.standard.data(forKey: "guestProfile")
            .flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }
    }

    private static func deleteAvatarFile(of profile: Profile) {
        guard let url = profile.avatarURL, url.isFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Profile.maxNameLength))
    }

    nonisolated private static func avatarJPEG(from image: UIImage) -> Data? {
        let side: CGFloat = 512
        let scale = max(side / image.size.width, side / image.size.height)
        let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (side - scaled.width) / 2, y: (side - scaled.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: scaled))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}

/// On-disk locations for profile data.
nonisolated enum ProfileFiles {
    /// Watch history and watchlist files that exist once per profile.
    static let perProfileData = ["continue-watching", "watchlist"]

    static var directory: URL {
        AppDirectories.support.appendingPathComponent("Profiles", isDirectory: true)
    }

    static var index: URL { directory.appendingPathComponent("profiles.json") }

    static var avatars: URL { directory.appendingPathComponent("Avatars", isDirectory: true) }

    /// The guest profile keeps the original single-profile file names, so its
    /// history carries over untouched.
    static func dataURL(_ base: String, profileID: String?) -> URL {
        let dir = AppDirectories.support
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let profileID, profileID != Profile.guestID else {
            return dir.appendingPathComponent("\(base).json")
        }
        return dir.appendingPathComponent("\(base)-\(profileID).json")
    }
}
