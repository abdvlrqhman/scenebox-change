"""Seeds a simulator's SceneBox container with a profile, watch progress,
a watchlist and a mix of downloads, so screenshots show real states.
`--empty` keeps the profile and clears everything else (a new viewer)."""
import json
import os
import shutil
import sys
import time

data = sys.argv[1]
empty = "--empty" in sys.argv[2:]
support = os.path.join(data, "Library", "Application Support")
docs = os.path.join(data, "Documents")
now = time.time() - 978307200  # Foundation's reference date (2001-01-01)

def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f)

def poster(imdb):
    return f"https://images.metahub.space/poster/medium/{imdb}/img"

write(os.path.join(support, "Profiles", "profiles.json"), [
    {"id": "guest", "name": "Me", "colorIndex": 1, "createdAt": now - 86400},
])

write(os.path.join(support, "continue-watching.json"), [
    {"id": "tt0903747", "mediaType": "series", "title": "Breaking Bad",
     "posterURLString": poster("tt0903747"), "season": 1, "episode": 3,
     "episodeID": "tt0903747:1:3", "positionSeconds": 900, "durationSeconds": 2880,
     "updatedAt": now - 600, "watchedEpisodes": ["S1E1", "S1E2"]},
    {"id": "tt1375666", "mediaType": "movie", "title": "Inception",
     "posterURLString": poster("tt1375666"), "positionSeconds": 4100,
     "durationSeconds": 8880, "updatedAt": now - 7200},
])

write(os.path.join(support, "watchlist.json"), [
    {"id": "tt0944947", "mediaType": "series", "title": "Game of Thrones",
     "posterURLString": poster("tt0944947"), "addedAt": now - 3000},
    {"id": "tt0816692", "mediaType": "movie", "title": "Interstellar",
     "posterURLString": poster("tt0816692"), "addedAt": now - 5000},
])

def record(rid, title, media, mtype, episode, complete, size, wants=None, path=None):
    return {
        "id": rid, "title": title, "releaseName": "Torrentio 1080p",
        "mediaID": media, "mediaType": mtype, "posterURLString": poster(media),
        "episodeLabel": episode,
        "magnetURI": f"magnet:?xt=urn:btih:{rid[:40]}&dn=sample",
        "totalBytes": size, "isComplete": complete, "addedAt": now - 100,
        "infoHash": rid[:40], "wantsRunning": wants, "localRelativePath": path,
    }

bb = "0123456789abcdef0123456789abcdef01234567"
inception = "fedcba9876543210fedcba9876543210fedcba98"
downloads = [
    record(bb + "-s1e1", "Breaking Bad", "tt0903747", "series", "S1E1", True, 1_450_000_000),
    record(bb + "-s1e2", "Breaking Bad", "tt0903747", "series", "S1E2", True, 1_380_000_000),
    record(bb + "-s1e3", "Breaking Bad", "tt0903747", "series", "S1E3", False, 1_410_000_000, True),
    record(bb + "-s1e4", "Breaking Bad", "tt0903747", "series", "S1E4", False, 1_390_000_000, True),
    record(inception, "Inception", "tt1375666", "movie", None, True, 2_600_000_000, path="Inception.webm"),
    record("1111111111111111111111111111111111111111", "Interstellar", "tt0816692", "movie", None, False, 3_100_000_000),
]
write(os.path.join(docs, "Downloads", "index.json"), downloads)
# A real (original, 10-minute still-frame) video, so the player and cast screens can open.
video = os.path.join(docs, "Downloads", inception, "Inception.webm")
os.makedirs(os.path.dirname(video), exist_ok=True)
shutil.copy(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "sample.webm"), video)

if empty:
    for name in ["continue-watching.json", "watchlist.json"]:
        write(os.path.join(support, name), [])
    write(os.path.join(docs, "Downloads", "index.json"), [])
print("seeded", data, "(empty)" if empty else "")
