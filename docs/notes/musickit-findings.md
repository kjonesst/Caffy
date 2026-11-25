# MusicKit findings

What MusicKit actually does on a device, as Caffy uses it. Each answer says how it was found (test, spike step, or console output) and on which iOS version. Nothing here is assumed: an open question stays open until a device run answers it.

This repo is public, so this file records behaviour and counts only, never song titles, playlist contents or anything else from a personal library.

## Open questions

### Does granting MusicKit authorization also authorize `MPMediaLibrary`?
Very likely yes, from indirect evidence. Not yet confirmed by `LiveAdapterTests/musicKitAuthorizationCoversMediaLibrary`.

- **Evidence (19 Nov 2026):** the listening coverage report from a fresh install of `com.kjonesst.caffy` showed "Music access: yes" and read 1,518 library songs through `MPMediaQuery`.
  - That report gets its songs from `MediaPlayerLibraryReader`, which returns `nil` unless `MPMediaLibrary.authorizationStatus() == .authorized`.
  - Caffy never calls `MPMediaLibrary.requestAuthorization`. The only music prompt it shows is `MusicAuthorization.request()`.
  - So MediaPlayer was authorized even though only MusicKit was asked.
- **Still to confirm:** the test's before and after lines, which show the change happening at the moment of the request (0 → 3), not just the end state.

### What does `MusicSubscription.current` return now that the App ID has MusicKit?
**It works, and no longer throws** (19 Nov 2026, from the `musickit-check` log on a device): `canPlayCatalogContent true, canBecomeSubscriber false, hasCloudLibraryEnabled true`.

- Before the paid team, this call always threw, so `libraryAccess()` returned `.unknown`. Now it returns `.canAddToLibrary`, which proves the MusicKit developer token is generated and accepted for `com.kjonesst.caffy`.
- `canBecomeSubscriber` is `false` because the account is already subscribed. It doesn't mean subscribing is blocked.
- Since a working token gives a real answer, `.unknown` now only means the check failed (offline, a server error). Onboarding no longer treats it as ready to publish playlists.

### Does a playlist's ID stay valid after it's renamed?
Open. Answered by the spike's rename test.

### How does `MusicLibrary.edit` behave when it replaces the whole track list?
Open: does it replace, append or dedupe, and are order and duplicates kept? Answered by the spike's edit test.

### Does a created playlist have a `url`, and does it open in Apple Music?
**It has one** (20 Nov 2026). Whether it opens in Apple Music gets checked in Task 3.

- `createPlaylist` returned a `Playlist` whose `url` is a share link of the form `https://music.apple.com/<storefront>/playlist/<name-slug>/pl.u-<id>`. The storefront is the account's ("in" here), and the slug comes from the playlist name.
- The link's `pl.u-…` id is **not** the library id Caffy stores (`p.…`). Library requests take the `p.…` id. The link is only for opening the playlist.
- Caffy saves the link with the playlist (`CaffyPlaylist.appleMusicURL` and the durable record). The slug follows the name, so after a rename the saved link may be stale. The rename test would show whether `url` changes.

### How many IDs can one `MusicCatalogResourceRequest` take?
**At least 100** (20 Nov 2026). A spike preview fetched all 244 catalog IDs for the current era in 3 requests (100, 100, 44), and every song came back with no decoding failures. Caffy keeps batches of 100. Larger batches haven't been tried, and there's no need to.

### Can an app set a playlist's cover image?
**No** (checked 21 Nov 2026 in the iOS 27.2 SDK):

- MusicKit's `MusicLibrary.createPlaylist` and `edit` take only a name, description, author display name and items.
- `Playlist.artwork` is read-only.
- MediaPlayer's `MPMediaPlaylistCreationMetadata` has only a name, author and description.

So Apple Music builds the cover from album art. Caffy shows a one-time guide after an era's first publish: the era's highlight photo, plus steps to set it as the cover in Apple Music.

- **25 Nov 2026:** the guide renders correctly on the device.
- **Album step (added 25 Nov 2026):** the photo goes into a "Caffinated" Photos album (`PhotoKitCoverAlbum`), and the guide says: ••• → Edit → tap the cover → Choose Photo → Albums → Caffinated.
- **The album is created on the device (25 Nov 2026).** iOS has no public way for an app to open a particular album in the Photos app. So tapping the guide's photo opens `CoverAlbumSheet`, which shows the album's photos inside Caffy, read live through PhotoKit.
- **Still to check on a device:**
  - that the wording matches Apple Music's screens
  - that Apple Music's photo picker shows the album
  - whether a limited Photos library allows making the album

## Decisions

### Publishing happens on tap
Decided 20 Nov 2026. Every era with songs shows "Listen in Apple Music". The first tap creates its playlist, and later taps bring it up to date and open it. A tap first checks the playlist is still in the on-device library, and makes it again if it was deleted. Nothing is published without a tap. Playlists keep the era's title, even where titles repeat, until era titles are made unique.

### Fallback for songs without a catalog ID
**Proposed, not decided.** For now, `PlaylistSongMatcher` leaves these songs out, giving the reason `noCatalogID`, and the spike's preview lists them.

The proposal, for songs whose id is `library-<persistentID>`:

1. **Search:** run `MusicCatalogSearchRequest(term: "<title> <artist>", types: [Song.self])` and keep the top 5 results.
2. **Normalise** both sides:
   - lowercase, and fold diacritics
   - remove bracketed version notes such as "(Remastered 2011)" or "[Live]", and trailing " - Live" or " - Remix" suffixes
   - remove "feat." and "ft." segments
   - collapse punctuation and whitespace
3. **Accept** a result only when all of these hold:
   - the normalised artist is exactly the same
   - the normalised title is exactly the same
   - the duration is within ±3 s. This needs `duration` added to `Song`, taken from `LibrarySongSnapshot.duration`.
4. **Otherwise** skip the song and list it in the report. Never pick the "closest" match.

In the current era, only 1 of 245 songs had no catalog ID: a DJ set that exists only as a library file, so a catalog search wouldn't find it either.

**My recommendation: don't build it yet.** Only 7 of 1,518 songs have no catalog ID (see Other device observations). A wrong match puts a song you never lived with into an "evidence" playlist, which costs more than leaving out a few imported files.

**Decision:** pending.

How much it matters: on 19 Nov 2026, 7 of 1,518 library songs (0.5%) had no catalog ID. With so few, skipping them and reporting each one may be enough, and the catalog search fallback may not be worth its risk of wrong matches.

## Other device observations

- **Bundle ID reset behaved as expected (19 Nov 2026):** the new app started recording from scratch.
  - 8 library reads on the first day saved 1,503 seeded plays, one for each song with a last-played date, and 0 observed plays.
  - The coverage verdict is "too early: 0 of 14 days", and the 14-day clock runs from 19 Nov 2026.
- **Era names repeat:** 57 eras in all, and the name "Spring at home" belongs to 4 of them, from different years.
  - The Task 2 spike must pick the current one by era ID or dates, never by name.
  - Published playlist names can collide in Apple Music too, so publishing should look playlists up by stored ID, never by name.
- **The current era is almost all seeded:** its playlist has 245 songs, 220 of them near plays, and every one of those 220 is seeded only.
  - With `seededPlaysNeedCorroboration` on, 176 would be dropped.
  - The listen-through after the Task 2 publish is what decides the flag.

- **First publish (20 Nov 2026):** the current era's playlist was published from the spike with 244 songs: 219 near plays, all seeded only, then 25 library additions.
  - Ken's first look: it "seemed to look fine". `seededPlaysNeedCorroboration` stays off unless a proper listen-through says otherwise.
- **The same song can appear twice under different catalog IDs:** 3 songs appear twice in the published list, with the same title and artist but different catalog IDs. Each looks like the same recording released on more than one album, such as a DJ-mix album and the original release.
  - `EraPlaylist` removes repeats by song ID, so it keeps both copies.
  - Removing repeats by normalised title + artist as well is a possible follow-up, not decided.

## Surprises

### Catalog lookup of 100 song IDs failed to decode (19 Nov 2026)
`MusicCatalogResourceRequest<Song>(matching: \.id, memberOf:)` for the current era's songs failed twice in a row, in batches of 100, with `DecodingError.dataCorrupted`, "The given data was not valid JSON … Unexpected end of file". The response body was empty or cut off.

**It didn't happen again.** On 20 Nov 2026, the same 244 IDs in the same batches of 100 all decoded on the first try. So the cause wasn't the batch size, and wasn't a particular ID. Most likely it was a temporary problem on Apple's side or the network's.

`CatalogBatcher` stays in as a safety net. It splits any batch that fails to decode and retries it, down to single IDs. A repeat of this failure then costs a few extra requests instead of the whole lookup, and the spike's preview logs which sizes and IDs failed. Any other error, such as being offline, is still thrown without splitting.
