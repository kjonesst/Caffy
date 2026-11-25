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

## Principles

- **Playlists are the evidence, not a tidy list.** An era's playlist is every song the evidence says the user lived with then, however many or few. There are no size caps and no padding: a busy era can hold 150 songs, and a short trip with no music stays empty.
- **Quality comes from evidence filters, not limits:** loose same-day plays are off by default, songs added but never played don't count, bulk import days and whole-album adds are thinned, and the order is near plays → library additions → loose plays.

## Tech

- Native Swift, built with Xcode, targeting iPhone.
- On-device only for the first version. No server unless a concrete need appears.
- Replaces an earlier React Native/Expo version that used the Spotify Web API.
- External services sit behind protocols so the app can run on fake data:
  - `ListeningSource`: Caffy's own recorded history (`RecordedListeningSource`), built from MediaPlayer library reads; sample plays for previews and tests
  - `PlaylistPublishing`: `LivePlaylistPublisher` writes with MusicKit's `MusicLibrary`; tests use a fake. `EraPublisher` drives it when a listen button is tapped.
  - `CatalogSongLookup`: catalog songs and cover art through MusicKit, cached in `CatalogArtwork`
- Era songs come from three sources, and each song keeps an evidence label (`SongEvidence`) saying which:
  - **Recorded plays** near a moment (`nearPlay`): the strongest evidence, and the only kind shown as "playing at" a moment.
  - **Last-played dates** on the same day as a moment (`loosePlay`): left out of era playlists by default (`includeLoosePlaysInEraPlaylist`), because matching single last-played dates put most of the library in the newest era.
  - **Library additions** (`libraryAdded`): songs whose `dateAdded` falls in the era (or up to 3 days before it), ranked by how much they were played since, with bulk-import days and whole-album adds thinned out (`LibraryAdditions`). This reaches back to before Caffy was installed, per era rather than per moment.
- Era playlists list near plays, then library additions, then (if on) loose plays (`EraPlaylist`). A moment's songs are `nil` until listening data reaches it, and `[]` once matched with nothing found; a moment without songs shows its era's, labelled "From this era".

## Status

Early stage. Eras are built from the real photo library. Listening comes from the `MediaPlayer` framework (`MPMediaQuery`), which needs no developer token and runs with free provisioning. Each time Caffy opens, it reads every library song's `lastPlayedDate` and `playCount`, compares them with the last read, and saves the plays in between (`ListeningRecorder`, `PlayHistoryDiff`). The latest play of a song is exact. Earlier ones are estimates over a time window, and windows longer than three days aren't matched to moments. The paid Apple Developer Program team is set up and the App ID (`com.kjonesst.caffy`) has the MusicKit service, so MusicKit code (playlists, catalog artwork) can now run on a device; what it does there is recorded in [MusicKit findings](docs/notes/musickit-findings.md). Moving from the old `caffytest1` bundle ID gave the app a fresh container, so listening recording restarted from the new app's first launch.

**Library additions (first device run):** the library's `dateAdded` starts in April 2020, but very little was added before 2023, so the 25 eras before then get nothing from it. The newest era had 155 songs played near its photos; they're real plays near real photos, so they're kept. The busiest addition days (2025-11-13: 71 songs, 2025-12-05: 64, 2026-09-03: 58, 2023-12-01: 44) were binges, not imports, so the bulk-day threshold went from 40 to 75. The 25-song cap on library additions per era was removed, and nested trips now take only the songs added during their own dates.

**Seeded plays (18 Nov 2026 coverage report, 6 days of recording):** the report showed 1,601 "exact" plays, but about 1,500 of them weren't plays the recorder saw. On the first library read, every song with a `lastPlayedDate` (1,503 songs) had been saved as one exact play at that date. Only about 100 plays had really happened while recording. "Spring at home" (2026-08-04 – now) had 256 songs: 234 near plus 24 added, with a couple in both. Those first-read plays are now **seeded** (`isSeeded` on `RecordedPlay` and `ListeningEvent`, with a one-off migration for existing rows). They're real timestamps, so they're kept and still match moments, but the coverage report counts them apart. It adds an "observed only" column and judges the verdict on that column, over moments since recording began. Era playlists order near songs by evidence: songs near more of the era's moments first, then songs with an observed play before seeded-only ones, then by score, title and id (before, the order was score, then the song seen first, then id). `EraBuildConfig.seededPlaysNeedCorroboration` (off) leaves out seeded-only songs that neither were added during the era nor have an observed play in it. The report's per-era line shows how many songs it would drop. Decision on the flag: pending Ken's listen-through of Spring at home.

Recorded history lives in its own local store (`ListeningHistoryStore`), apart from the derived eras, so rebuilding eras never loses it. DEBUG builds have **Listening coverage** in the profile button's menu: a report of how many moments real listening covers, with the go/no-go verdict below.

## Roadmap

1. Read photos with PhotoKit, cluster them by time and distance, and show moment cards.
2. Use fake listening data to build the matching logic and collage.
3. Validate listening snapshots on a real iPhone (built, not yet run on a device): record for two weeks, opening Caffy at least once a day, then read the Listening coverage report. **Pass:** at least 40% of the moments since recording began have songs played near them, counting only plays Caffy saw happen (not seeded last-played dates), and 7 of 10 spot-checked matches are right. **Borderline (20–40%):** try background recording first. **Fail (under 20%):** music becomes era-level only (genres and listening profile), and Caffy becomes photo-led. Set the thresholds before recording starts.
4. Create and edit one test playlist, then connect publishing to moments.
5. Add `CLVisit`, background work, and notifications.

Step 3 is the main validation point. If snapshots turn out to be too unreliable, the concept gets revisited before any UI polish.

## Design

The Home and Library screens come from the [Caffy Home and Library](https://claude.ai/artifact/DraouELjd2r5fLAQHe8vn9) Claude design. Onboarding (`Caffy/Views/Onboarding`) is seven steps: welcome, the problem, how it works, privacy, Apple Music, Photos, and ready. Its hero, `MemoryBurst`, is a native SwiftUI port of the 21st.dev "LogoBurst" component, with photo and playlist artwork added. All onboarding copy lives in `OnboardingCopy.swift`. Bricolage Grotesque, DM Mono, and Reenie Beanie are bundled in `Caffy/Resources/Fonts` under the SIL Open Font License. Not designed yet: the Profile screen and empty states.

DEBUG builds have a few shortcuts for working on onboarding: the profile button's menu has **Replay onboarding**, `-onboardingStep <1–7>` opens a given step, and `-fakePermissions <preset>` (for example `musicDenied`, `noSubscription`, `photosLimited`, `allGranted`) fakes a permission outcome, which the simulator needs because it has no Apple Music.

## Known constraints

- **Listening history:** Apple's recently played data has no play timestamps and is reportedly limited to about 30 items. Caffy builds its own history by comparing MediaPlayer reads of library songs (`lastPlayedDate`, `playCount`). Only library songs are seen. Catalog songs played without being added are missed, and plays from other devices arrive only as estimates.
- **The newest era is always the richest:** `lastPlayedDate` keeps only each song's last play, so every song replayed recently lands in the newest era, and its older plays are gone. Older eras fill in only from recorded history over time, or from importing Apple's privacy export.
- **Seeded plays are one per song:** the first library read saves each song's last-played date as a seeded play. These plays are real, so they're kept, but they're tagged and ordered after stronger evidence (more moments, observed plays). Turn on `seededPlaysNeedCorroboration` to leave out the ones nothing else backs up.
- **Recording needs the app open:** plays are only recorded when Caffy opens, until background recording (`BGAppRefreshTask`) exists. The longer between opens, the vaguer the estimates.
- **History is per-device:** the listening history store is local and never synced (iCloud Music Library already syncs play counts, so two devices would count each play twice).
- **Library ids change:** a song's `persistentID` can change after a library reset or an iCloud Music Library resync. Catalog songs keep their id; for others, the next read starts a fresh baseline.
- **Playlists:** `MusicLibrary.shared.edit` replaces the full track list, and Caffy only edits playlists it created. Playlists are published only when the user taps "Listen in Apple Music" on an era; each tap creates the playlist, or brings it up to date, and opens it. Eras with no songs have no button.
- **Playlist covers:** no Apple API lets an app set a playlist's cover image (MusicKit's `createPlaylist` and `edit` take a name, description and songs only), so Apple Music uses album art. After an era's first publish, Caffy adds the era's highlight photo to a "Caffinated" album in Photos (a reference, not a copy; once per playlist) and shows how to set it as the cover from that album in Apple Music. If the album can't be written (for example without Photos access), the guide still shows the photo, without the album step.
- **Playlist names:** a playlist is named after its era, and era titles can repeat (several "Spring at home"), so playlist names can too until era titles are made unique.
- **Nothing from before the library's real additions:** library additions only reach back as far as songs were actually added. In Ken's library that's 2023, so the Kerala and Thiruvananthapuram eras stay empty until per-play history is imported.
- **Short trips may have few or no songs:** people rarely add or play much music while travelling, and that's accurate, so trips aren't padded with songs from around them.
- **Library additions are a proxy:** adding a song isn't the same as listening to it, and people who stream without adding songs to their library get little from it. `dateAdded` can also be reset by a library resync, which piles the whole library onto one day (the coverage report warns when one day holds 30% or more).
- **Genre river:** The river goes back years, but Caffy can only record listening from the day it's installed. Its widths are sample data until a real source for older history is found.
- **Location:** The first version uses photo time and location metadata to avoid needing Always location access. `CLVisit` comes later.
- **Background work:** MusicKit reads and playlist edits may not work reliably in the background, so work must also finish when the app opens.
- **Accounts:** MusicKit needs a paid Apple Developer Program membership, and full catalog access needs an Apple Music subscription.

## Open questions

- Where does per-moment history from before Caffy was installed come from? Library additions cover eras, not moments, and nothing before 2023 in Ken's library. The Apple privacy export (per-play history) is the likely answer, if Apple Music was in use then: **request the export now**, since it takes days to arrive.
- How often has `dateAdded` been reset by resyncs in real libraries?
- How are era boundaries, titles, and summaries generated automatically?
- Is `lastPlayedDate` reliable enough on current iOS? (Testable now on a real iPhone with the Listening coverage report.)
- Does granting Apple Music access (MusicKit) also authorize `MPMediaLibrary` on a device?
- How can listening history cover more than one device?
- Can MusicKit reads and playlist edits run in the background?
- Does renaming a playlist keep its ID usable for updates?
- Are there App Review or MusicKit terms issues for a non-playback app that writes to the library?

None of the Apple API behaviour above is verified on a device yet. `LiveAdapterTests/mediaPlayerReadsLibrary` checks the MediaPlayer side when run on an iPhone.
