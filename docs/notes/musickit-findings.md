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
Open.

### How many IDs can one `MusicCatalogResourceRequest` take?
Open. Caffy batches 100 at a time until this is checked.

## Decisions

### Fallback for songs without a catalog ID
Proposed, not decided. See the Task 2 proposal; this section records the decision once it's made.

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

## Surprises

None yet.
