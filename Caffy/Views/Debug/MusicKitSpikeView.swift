#if DEBUG
import OSLog
import SwiftData
import SwiftUI

/// DEBUG only: answers the MusicKit questions that need a real library (see
/// docs/notes/musickit-findings.md).
///
/// It may only write to one playlist: the current "Spring at home" era's,
/// found by era id, not by name. Previewing is read-only; publishing, the
/// rename test and the edit test each ask before they write, and the tests
/// put the playlist back as it was. Results go to the log below and to the
/// console under the `spike` category.
struct MusicKitSpikeView: View {
    /// The only era whose playlist this screen may write to.
    static let eraTitle = "Spring at home"
    static let testName = "Spring at home · test"
    static let playlistDescription = "Made by Caffy from the music you lived with in this era."

    enum Step: String, Identifiable {
        case publish, renameTest, editTest
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Era> { $0.endDate == nil }) private var openEras: [Era]

    @State private var match: PlaylistSongMatch?
    @State private var lines: [String] = []
    @State private var isWorking = false
    @State private var confirming: Step?

    private let publisher = LivePlaylistPublisher()
    private static let logger = Logger(subsystem: "com.kjonesst.caffy", category: "spike")

    /// The current era called "Spring at home". Other eras with the same name
    /// are in the past, so never match.
    private var era: Era? {
        openEras.first { $0.title == Self.eraTitle && $0.eraID != nil }
    }

    private var ledger: PlaylistLedger { PlaylistLedger(context: modelContext) }

    private var link: PlaylistLink? {
        guard let eraID = era?.eraID else { return nil }
        return try? ledger.link(forEraID: eraID)
    }

    private var canPublish: Bool {
        !isWorking && link == nil && !(match?.catalogIDs.isEmpty ?? true)
    }

    /// The tests compare against the preview, so it must match what's published.
    private var canTest: Bool {
        !isWorking && link != nil && match?.catalogIDs == link?.songIDs
    }

    var body: some View {
        NavigationStack {
            List {
                eraSection
                stepsSection
                if let match { previewSections(match) }
                if !lines.isEmpty {
                    Section("Log") {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("MusicKit spike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if match != nil || !lines.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: reportText)
                    }
                }
            }
            .overlay {
                if isWorking { ProgressView() }
            }
            .confirmationDialog(
                confirming.map(title(for:)) ?? "",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                titleVisibility: .visible,
                presenting: confirming
            ) { step in
                Button(title(for: step)) { Task { await run(step) } }
                Button("Cancel", role: .cancel) {}
            } message: { step in
                Text(message(for: step))
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var eraSection: some View {
        Section("Era") {
            if let era {
                LabeledContent("Title", value: era.title)
                LabeledContent("Since", value: era.startDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Era ID", value: era.eraID ?? "–")
                LabeledContent("Songs in era playlist", value: "\(era.songs.count)")
                LabeledContent("Apple Music playlist", value: link?.playlistID ?? "Not published")
            } else {
                Text("There's no current era called “\(Self.eraTitle)”, so nothing can be written.")
            }
        }
    }

    private var stepsSection: some View {
        Section {
            Button("1. Preview the track list") { Task { await preview() } }
                .disabled(era == nil || isWorking)
            Button("2. Publish…") { confirming = .publish }
                .disabled(!canPublish)
            Button("3. Rename test…") { confirming = .renameTest }
                .disabled(!canTest)
            Button("4. Edit test…") { confirming = .editTest }
                .disabled(!canTest)
        } header: {
            Text("Steps")
        } footer: {
            Text("Only step 1 is read-only. Steps 2–4 write to this one playlist in your Apple Music library, and each asks first. Steps 3 and 4 need a preview that matches what was published.")
        }
    }

    @ViewBuilder private func previewSections(_ match: PlaylistSongMatch) -> some View {
        Section("Will publish \(match.matched.count) songs, in this order") {
            ForEach(Array(match.matched.enumerated()), id: \.offset) { index, matched in
                Text(Self.line(index + 1, matched))
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        if !match.unmatched.isEmpty {
            Section("Left out: \(match.unmatched.count)") {
                ForEach(Array(match.unmatched.enumerated()), id: \.offset) { _, unmatched in
                    Text("\(unmatched.song.song.title) – \(unmatched.song.song.artist) · \(unmatched.reason.rawValue)")
                        .font(.system(.footnote, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Steps

    private func preview() async {
        guard let era else { return }
        isWorking = true
        defer { isWorking = false }
        note("preview: era \(era.eraID ?? "–"), \(era.songs.count) songs in its playlist")
        do {
            let found = try await PlaylistSongMatcher.match(era.songs, lookup: LiveCatalogSongLookup())
            match = found
            let noID = found.unmatched.count { $0.reason == .noCatalogID }
            note("preview: \(found.matched.count) matched, \(found.unmatched.count) left out "
                + "(no catalog id \(noID), not in catalog \(found.unmatched.count - noID))")
        } catch {
            note("preview failed: \(error)")
        }
    }

    private func run(_ step: Step) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch step {
            case .publish: try await publish()
            case .renameTest: try await renameTest()
            case .editTest: try await editTest()
            }
        } catch {
            note("\(step.rawValue) stopped: \(error)")
            if step != .publish {
                note("The playlist may not be back as it was. Run the same step again: it ends by restoring it.")
            }
        }
    }

    private func publish() async throws {
        guard let eraID = era?.eraID, let match, link == nil else { return }
        let outcome = try await PlaylistSync(publisher: publisher).publish(
            name: Self.eraTitle, description: Self.playlistDescription,
            songIDs: match.catalogIDs, link: nil, now: .now
        )
        note("publish: \(Self.describe(outcome))")
        guard let published = outcome.link else { return }
        try ledger.save(published, forEraID: eraID)
        if let fetched = try await publisher.playlist(id: published.playlistID) {
            note("after publish: url \(fetched.url?.absoluteString ?? "none"); \(Self.compare(fetched, to: match.matched.map(\.catalog)))")
        } else {
            note("after publish: NOT FOUND by id \(published.playlistID)")
        }
    }

    private func renameTest() async throws {
        guard let link else { return }
        let id = link.playlistID

        let renamed = try await publisher.rename(id, to: Self.testName)
        note("rename: returned id \(renamed.id) (same as before: \(Self.yes(renamed.id == id))), name “\(renamed.name)”")
        let afterRename = try await publisher.playlist(id: id)
        note("fetch by the original id after renaming: "
            + (afterRename.map { "found, id \($0.id), name “\($0.name)”, url \($0.url?.absoluteString ?? "none")" } ?? "NOT FOUND"))

        let back = try await publisher.rename(id, to: link.name)
        let afterBack = try await publisher.playlist(id: id)
        note("rename back: name “\(back.name)”; fetch again: " + (afterBack.map { "found, name “\($0.name)”" } ?? "NOT FOUND"))
    }

    private func editTest() async throws {
        guard let link, let match, match.catalogIDs == link.songIDs else { return }
        let base = match.matched.map(\.catalog)

        try await replace(link.playlistID, with: base.reversed(), label: "reversed order")
        if let first = base.first {
            try await replace(link.playlistID, with: base + [first], label: "plus a repeat of the first song")
        }
        try await replace(link.playlistID, with: Array(base.prefix(max(base.count / 2, 1))), label: "first half only")
        try await replace(link.playlistID, with: base, label: "restore")
    }

    private func replace(_ id: String, with songs: [CatalogSong], label: String) async throws {
        let returned = try await publisher.replaceTracks(of: id, with: songs.map(\.id))
        let fetched = try await publisher.playlist(id: id)
        note("edit, \(label): sent \(songs.count); edit returned \(returned.tracks.count) tracks, id same: \(Self.yes(returned.id == id)); "
            + "fetched: " + (fetched.map { Self.compare($0, to: songs) } ?? "NOT FOUND"))
    }

    // MARK: - Text

    private func note(_ line: String) {
        lines.append(line)
        Self.logger.notice("[spike] \(line, privacy: .public)")
    }

    private func title(for step: Step) -> String {
        switch step {
        case .publish: "Publish to Apple Music"
        case .renameTest: "Run the rename test"
        case .editTest: "Run the edit test"
        }
    }

    private func message(for step: Step) -> String {
        let count = match?.matched.count ?? 0
        switch step {
        case .publish:
            return "Creates one playlist called “\(Self.eraTitle)” in your Apple Music library, with the \(count) songs from the preview in that order. Nothing else in your library changes."
        case .renameTest:
            return "Renames that playlist to “\(Self.testName)”, looks it up by its id, renames it back to “\(Self.eraTitle)”, and looks it up again. It ends with the original name."
        case .editTest:
            return "Replaces that playlist's tracks four times, looking it up after each: reversed order; the list plus one repeat of the first song; the first half only; then the \(count) published songs again. It ends with exactly the published list."
        }
    }

    private var reportText: String {
        var text = ["Caffy MusicKit spike, \(Date.now.formatted())"]
        if let match {
            text.append("")
            text.append("Will publish \(match.matched.count) songs:")
            text += match.matched.enumerated().map { Self.line($0.offset + 1, $0.element) }
            if !match.unmatched.isEmpty {
                text.append("")
                text.append("Left out \(match.unmatched.count):")
                text += match.unmatched.map { "\($0.song.song.title) – \($0.song.song.artist) · \($0.reason.rawValue)" }
            }
        }
        if !lines.isEmpty {
            text.append("")
            text.append("Log:")
            text += lines
        }
        return text.joined(separator: "\n")
    }

    private static func line(_ number: Int, _ matched: PlaylistSongMatch.Matched) -> String {
        let song = matched.song
        let seeded = song.evidence == .nearPlay && song.hasObservedPlay == false ? " (seeded only)" : ""
        return "\(number). \(matched.catalog.title) – \(matched.catalog.artist) · \(song.evidence.rawValue)\(seeded)"
    }

    /// How a fetched playlist compares with the songs sent. Library tracks
    /// have their own ids, so songs are compared by title and artist.
    static func compare(_ playlist: PublishedPlaylist, to expected: [CatalogSong]) -> String {
        let got = playlist.tracks.map { key($0.title, $0.artist) }
        let want = expected.map { key($0.title, $0.artist) }
        let missing = Set(want).subtracting(got).count
        return "\(got.count) tracks (expected \(want.count)) · same order: \(yes(got == want)) · "
            + "same songs: \(yes(Set(got) == Set(want))) (\(missing) expected not found) · repeats: \(got.count - Set(got).count)"
    }

    private static func key(_ title: String, _ artist: String) -> String {
        "\(title)|\(artist)".lowercased()
    }

    private static func yes(_ value: Bool) -> String { value ? "yes" : "NO" }

    private static func describe(_ outcome: PlaylistPublishOutcome) -> String {
        switch outcome {
        case .created(let link): "created id \(link.playlistID), url \(link.url?.absoluteString ?? "none"), \(link.songIDs.count) songs"
        case .updated(let link, let renamed, let replaced): "updated id \(link.playlistID) (renamed \(renamed), tracks replaced \(replaced))"
        case .unchanged(let link): "unchanged id \(link.playlistID)"
        case .missing(let link): "missing: no playlist with id \(link.playlistID)"
        case .nothingToPublish: "nothing to publish"
        }
    }
}
#endif
