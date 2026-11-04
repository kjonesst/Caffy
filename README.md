# Caffy

Caffy is an iOS companion app for Apple Music. It automatically connects your photos and places to the music you were listening to, then turns those overlaps into **moments**: a collage plus a self-updating Apple Music playlist.

## How it works

1. **Capture:** Store photos, visits, and song plays as timestamped records.
2. **Match:** Cluster nearby photos into moments, then attach songs played in the same time window.
3. **Publish:** Create or update an app-owned Apple Music playlist for each moment.
4. **Display:** Show the collage and send a notification when a moment or playlist is ready.

## Product principles

- **Automatic capture.** No manual pinning. Users value the result, not the process.
- **No in-app playback.** Caffy pushes playlists to the user's Apple Music library.
- **Dashboard / collage.** The app is where photos and music come together.
- **Notify and invite.** When a playlist updates, tell the user and invite them to listen.
- **Apple Music first.**

## Tech

- Native Swift, built with Xcode, targeting iPhone.
- On-device only for the first version. No server unless a concrete need appears.
- Replaces an earlier React Native/Expo version that used the Spotify Web API.
- External services sit behind protocols so the app can run on fake data:
  - `ListeningSource`: fake sample plays now, MusicKit later
  - `PlaylistPublishing`: fake logger now, `MusicLibrary` later

## Status

Early stage. The paid Apple Developer Program membership has not been purchased yet, so MusicKit code can't be run or validated. Until then, the app is built against protocols and fake data.

## Roadmap

1. Read photos with PhotoKit, cluster them by time and distance, and show moment cards.
2. Use fake listening data to build the matching logic and collage.
3. After joining the Developer Program, build a debug screen that logs real listening snapshots and compare them with actual listening over several days.
4. Create and edit one test playlist, then connect publishing to moments.
5. Add `CLVisit`, background work, and notifications.

Step 3 is the main validation point. If snapshots turn out to be too unreliable, the concept gets revisited before any UI polish.

## Known constraints

- **Listening history:** Apple's recently played data has no play timestamps and is reportedly limited to about 30 items. Caffy has to build its own history by saving snapshots and comparing them (`lastPlayedDate`, `playCount` for library songs; estimated time ranges for others). Plays on other devices may be missed.
- **Playlists:** `MusicLibrary.shared.edit` replaces the full track list, and Caffy only edits playlists it created.
- **Location:** The first version uses photo time and location metadata to avoid needing Always location access. `CLVisit` comes later.
- **Background work:** MusicKit reads and playlist edits may not work reliably in the background, so work must also finish when the app opens.
- **Accounts:** MusicKit needs a paid Apple Developer Program membership, and full catalog access needs an Apple Music subscription.

## Open questions

- Is `lastPlayedDate` reliable enough on current iOS?
- Can MusicKit reads and playlist edits run in the background?
- Does renaming a playlist keep its ID usable for updates?
- Are there App Review or MusicKit terms issues for a non-playback app that writes to the library?

None of the Apple API behaviour above is verified yet. It needs testing on a real device.
