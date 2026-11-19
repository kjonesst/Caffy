# MusicKit findings

What MusicKit actually does on a device, as Caffy uses it. Each answer says how it was found (test, spike step, or console output) and on which iOS version. Nothing here is assumed: an open question stays open until a device run answers it.

This repo is public, so this file records behaviour and counts only, never song titles, playlist contents or anything else from a personal library.

## Open questions

### Does granting MusicKit authorization also authorize `MPMediaLibrary`?
Open. Answered by `LiveAdapterTests/musicKitAuthorizationCoversMediaLibrary` on a fresh install.

### What does `MusicSubscription.current` return now that the App ID has MusicKit?
Open. Before the paid team it always threw, so `libraryAccess()` returned `.unknown`. Answered by `LiveAdapterTests/musicSubscriptionState` and the `musickit-check` log on the onboarding Apple Music step.

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

## Surprises

None yet.
