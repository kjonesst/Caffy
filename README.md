# Caffy

Caffy is an iOS companion app for Apple Music. It automatically connects your photos and places to the music you were listening to, then groups those overlaps into **eras**: chapters of your life, each with a photo collage and a self-updating Apple Music playlist.

## How it works

1. **Capture:** Store photos, visits, and song plays as timestamped records.
2. **Match:** Cluster nearby photos into moments, attach songs played in the same time window, and group moments into eras.
3. **Publish:** Create or update an app-owned Apple Music playlist for each era.
4. **Display:** Show each era's collage, chart how listening moved on the genre river, and send a notification when an era or playlist is ready.

## Product principles

- **Automatic capture.** No manual pinning. Users value the result, not the process.
- **No in-app playback.** Caffy pushes playlists to the user's Apple Music library.
- **Dashboard / collage.** The app is where photos and music come together: era cards on Home, the genre river in Library.
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

Early stage. The Home and Library designs are built on sample data, with placeholder photos and cover art. The paid Apple Developer Program membership has not been purchased yet, so MusicKit code can't be run or validated. Until then, the app is built against protocols and fake data.

## Roadmap

1. Read photos with PhotoKit, cluster them by time and distance, and show moment cards.
2. Use fake listening data to build the matching logic and collage.
3. After joining the Developer Program, build a debug screen that logs real listening snapshots and compare them with actual listening over several days.
4. Create and edit one test playlist, then connect publishing to moments.
5. Add `CLVisit`, background work, and notifications.

Step 3 is the main validation point. If snapshots turn out to be too unreliable, the concept gets revisited before any UI polish.

## Design

The Home and Library screens come from the [Caffy Home and Library](https://claude.ai/artifact/DraouELjd2r5fLAQHe8vn9) Claude design. Bricolage Grotesque, DM Mono, and Reenie Beanie are bundled in `Caffy/Resources/Fonts` under the SIL Open Font License. Not designed yet: the Profile screen, empty states, and the permissions flow.

## Known constraints

- **Listening history:** Apple's recently played data has no play timestamps and is reportedly limited to about 30 items. Caffy has to build its own history by saving snapshots and comparing them (`lastPlayedDate`, `playCount` for library songs; estimated time ranges for others). Plays on other devices may be missed.
- **Playlists:** `MusicLibrary.shared.edit` replaces the full track list, and Caffy only edits playlists it created.
- **Genre river:** The river goes back years, but Caffy can only record listening from the day it's installed. Its widths are sample data until a real source for older history is found.
- **Location:** The first version uses photo time and location metadata to avoid needing Always location access. `CLVisit` comes later.
- **Background work:** MusicKit reads and playlist edits may not work reliably in the background, so work must also finish when the app opens.
- **Accounts:** MusicKit needs a paid Apple Developer Program membership, and full catalog access needs an Apple Music subscription.

## Open questions

- Where does history from before Caffy was installed come from, for older eras and the genre river?
- How are era boundaries, titles, and summaries generated automatically?
- Is `lastPlayedDate` reliable enough on current iOS?
- Can MusicKit reads and playlist edits run in the background?
- Does renaming a playlist keep its ID usable for updates?
- Are there App Review or MusicKit terms issues for a non-playback app that writes to the library?

None of the Apple API behaviour above is verified yet. It needs testing on a real device.
