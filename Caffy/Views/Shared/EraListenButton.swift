import SwiftUI

/// "Listen in Apple Music" for one era: publishes its playlist on the first
/// tap (through `EraPublisher`), then opens it.
///
/// After an era's first publish, it shows `CoverGuideSheet` so the user can
/// set the era's highlight photo as the cover, since apps can't. Later taps
/// go straight to Apple Music. Draws nothing for eras with no songs, sample
/// eras, or where there's no publisher (previews).
struct EraListenButton: View {
    enum Style {
        /// The big pill on a Home card.
        case pill(EraPalette)
        /// The plain bar above an era's full song list.
        case plain
    }

    let era: Era
    let style: Style

    @Environment(EraPublisher.self) private var publisher: EraPublisher?
    @Environment(PermissionsManager.self) private var permissions: PermissionsManager?
    @Environment(\.openURL) private var openURL
    @AppStorage("showsCoverGuide") private var showsCoverGuide = true
    @State private var coverGuide: CoverGuide?

    private struct CoverGuide: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        if let publisher, EraPublisher.canListen(to: era) {
            let display = Self.display(for: publisher.state(for: era))
            Group {
                switch style {
                case .pill(let palette): ListenPill(palette: palette, display: display, action: tap)
                case .plain: PlainListenButton(display: display, action: tap)
                }
            }
            .sheet(item: $coverGuide) { guide in
                CoverGuideSheet(era: era, playlistURL: guide.url)
            }
        }
    }

    private func tap() {
        guard let publisher else { return }
        // Where the fix is in Settings, the button takes the user there.
        if case .failed(let failure) = publisher.state(for: era), Self.opensSettings(failure) {
            openURL(PermissionsManager.settingsURL)
            return
        }
        Task {
            if let permissions, permissions.music == .notDetermined {
                await permissions.requestMusic()
            }
            guard let result = await publisher.listen(
                to: era,
                music: permissions?.music ?? .notDetermined,
                library: permissions?.library ?? .unknown
            ) else { return }
            if result.isFirstPublish && showsCoverGuide && era.highlightMoment != nil {
                coverGuide = CoverGuide(url: result.url)
            } else {
                openURL(result.url)
            }
        }
    }

    static func opensSettings(_ failure: EraPublisher.Failure) -> Bool {
        switch failure {
        case .musicAccess(.denied), .libraryAccess(.syncLibraryOff): true
        default: false
        }
    }

    /// What the button says in each state.
    static func display(for state: EraPublisher.State) -> ListenDisplay {
        switch state {
        case .idle:
            return .ready
        case .publishing:
            return ListenDisplay(title: String(localized: "Making your playlist…"), isWorking: true)
        case .failed(let failure):
            let title: String = switch failure {
            case .musicAccess(.denied): String(localized: "Allow Apple Music in Settings")
            case .musicAccess(.restricted): String(localized: "Apple Music is restricted on this iPhone")
            case .musicAccess: String(localized: "Connect Apple Music to listen")
            case .libraryAccess(.syncLibraryOff): String(localized: "Turn on Sync Library in Settings")
            case .libraryAccess: String(localized: "Needs an Apple Music subscription")
            case .nothingPublishable: String(localized: "None of these songs are in Apple Music")
            case .couldNotReach: String(localized: "Couldn't reach Apple Music. Tap to try again")
            }
            return ListenDisplay(title: title, isProblem: true)
        }
    }
}
