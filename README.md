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
  - `ListeningSource`: Caffy's own recorded history (`RecordedListeningSource`), built from MediaPlayer library reads; sample plays for previews and tests
  - `PlaylistPublishing`: fake logger now, `MusicLibrary` later

## Status

Early stage. Eras are built from the real photo library. Listening comes from the `MediaPlayer` framework (`MPMediaQuery`), which needs no developer token and runs with free provisioning. Each time Caffy opens, it reads every library song's `lastPlayedDate` and `playCount`, compares them with the last read, and saves the plays in between (`ListeningRecorder`, `PlayHistoryDiff`). The latest play of a song is exact. Earlier ones are estimates over a time window, and windows longer than three days aren't matched to moments. The paid Apple Developer Program membership has not been purchased yet, so MusicKit code (playlists, catalog artwork) can't be run or validated.

Recorded history lives in its own local store (`ListeningHistoryStore`), apart from the derived eras, so rebuilding eras never loses it. DEBUG builds have **Listening coverage** in the profile button's menu: a report of how many moments real listening covers, with the go/no-go verdict below.

## Roadmap

1. Read photos with PhotoKit, cluster them by time and distance, and show moment cards.
2. Use fake listening data to build the matching logic and collage.
3. Validate listening snapshots on a real iPhone (built, not yet run on a device): record for two weeks, opening Caffy at least once a day, then read the Listening coverage report. **Pass:** at least 40% of the last 30 days' moments have songs played near them, and 7 of 10 spot-checked matches are right. **Borderline (20–40%):** try background recording first. **Fail (under 20%):** music becomes era-level only (genres and listening profile), and Caffy becomes photo-led. Set the thresholds before recording starts.
4. Create and edit one test playlist, then connect publishing to moments.
5. Add `CLVisit`, background work, and notifications.

Step 3 is the main validation point. If snapshots turn out to be too unreliable, the concept gets revisited before any UI polish.

## Design

The Home and Library screens come from the [Caffy Home and Library](https://claude.ai/artifact/DraouELjd2r5fLAQHe8vn9) Claude design. Onboarding (`Caffy/Views/Onboarding`) is seven steps: welcome, the problem, how it works, privacy, Apple Music, Photos, and ready. Its hero, `MemoryBurst`, is a native SwiftUI port of the 21st.dev "LogoBurst" component, with photo and playlist artwork added. All onboarding copy lives in `OnboardingCopy.swift`. Bricolage Grotesque, DM Mono, and Reenie Beanie are bundled in `Caffy/Resources/Fonts` under the SIL Open Font License. Not designed yet: the Profile screen and empty states.

DEBUG builds have a few shortcuts for working on onboarding: the profile button's menu has **Replay onboarding**, `-onboardingStep <1–7>` opens a given step, and `-fakePermissions <preset>` (for example `musicDenied`, `noSubscription`, `photosLimited`, `allGranted`) fakes a permission outcome, which the simulator needs because it has no Apple Music.

## Known constraints

- **Listening history:** Apple's recently played data has no play timestamps and is reportedly limited to about 30 items. Caffy builds its own history by comparing MediaPlayer reads of library songs (`lastPlayedDate`, `playCount`). Only library songs are seen. Catalog songs played without being added are missed, and plays from other devices arrive only as estimates.
- **Recording needs the app open:** plays are only recorded when Caffy opens, until background recording (`BGAppRefreshTask`) exists. The longer between opens, the vaguer the estimates.
- **History is per-device:** the listening history store is local and never synced (iCloud Music Library already syncs play counts, so two devices would count each play twice).
- **Library ids change:** a song's `persistentID` can change after a library reset or an iCloud Music Library resync. Catalog songs keep their id; for others, the next read starts a fresh baseline.
- **Playlists:** `MusicLibrary.shared.edit` replaces the full track list, and Caffy only edits playlists it created.
- **Genre river:** The river goes back years, but Caffy can only record listening from the day it's installed. Its widths are sample data until a real source for older history is found.
- **Location:** The first version uses photo time and location metadata to avoid needing Always location access. `CLVisit` comes later.
- **Background work:** MusicKit reads and playlist edits may not work reliably in the background, so work must also finish when the app opens.
- **Accounts:** MusicKit needs a paid Apple Developer Program membership, and full catalog access needs an Apple Music subscription.

## Open questions

- Where does history from before Caffy was installed come from, for older eras and the genre river?
- How are era boundaries, titles, and summaries generated automatically?
- Is `lastPlayedDate` reliable enough on current iOS? (Testable now on a real iPhone with the Listening coverage report.)
- Does granting Apple Music access (MusicKit) also authorize `MPMediaLibrary` on a device?
- How can listening history cover more than one device?
- Can MusicKit reads and playlist edits run in the background?
- Does renaming a playlist keep its ID usable for updates?
- Are there App Review or MusicKit terms issues for a non-playback app that writes to the library?

None of the Apple API behaviour above is verified on a device yet. `LiveAdapterTests/mediaPlayerReadsLibrary` checks the MediaPlayer side when run on an iPhone.
