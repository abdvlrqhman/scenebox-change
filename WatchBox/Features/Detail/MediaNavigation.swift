//
//  MediaNavigation.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import SwiftUI

/// Push a title page that starts playing straight away (Home's Play buttons).
struct PlayTitle: Hashable {
    let item: MediaResult
}

struct CatalogDestination: Hashable {
    let type: MediaType
    let feed: CatalogFeed
    var genre: String? = nil
}

extension View {
    func mediaNavigationDestinations() -> some View {
        self
            .navigationDestination(for: MediaResult.self) { item in
                MediaDetailView(mediaID: item.id, type: item.type, fallbackTitle: item.name)
                    .id(item.id)
            }
            .navigationDestination(for: PlayTitle.self) { play in
                MediaDetailView(mediaID: play.item.id, type: play.item.type, fallbackTitle: play.item.name,
                                autoplay: true)
                    .id(play.item.id)
            }
            .navigationDestination(for: CastMember.self) { member in
                ActorView(member: member)
            }
            .navigationDestination(for: PersonCredit.self) { credit in
                ResolvingDetailView(credit: credit)
            }
    }
}
