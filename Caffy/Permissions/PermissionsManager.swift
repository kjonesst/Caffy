import Foundation
import Observation
import UIKit

/// Whether Caffy may read the user's Apple Music data.
enum MusicAccess: Equatable {
    case notDetermined
    case authorized
    case denied
    /// Blocked by the device, for example by Screen Time. The user can't
    /// change it from Caffy's settings.
    case restricted
}

/// Whether Caffy can put catalog songs into the user's library, which its
/// playlists need.
enum MusicLibraryAccess: Equatable {
    /// Not checked yet, or the check failed. Without the paid Developer
    /// Program (no MusicKit developer token), it always fails, so this stays
    /// quiet rather than showing an error.
    case unknown
    case canAddToLibrary
    /// No Apple Music subscription. `canSubscribe` is false when, for
    /// example, Apple Music isn't offered in their region.
    case needsSubscription(canSubscribe: Bool)
    /// Subscribed, but Sync Library is off, so playlists can't be added.
    case syncLibraryOff
}

/// Whether Caffy may read the user's photos.
enum PhotoAccess: Equatable {
    case notDetermined
    case full
    /// The user picked which photos Caffy sees. Still a success.
    case limited
    case denied
    case restricted

    var isGranted: Bool { self == .full || self == .limited }
}

/// Keeps track of Caffy's Apple Music and Photos permissions, and asks for
/// them. Onboarding uses it now; the main app can use the same instance later.
///
/// The system calls sit behind `PermissionsClient`, so previews and the
/// `-fakePermissions` launch argument can show every outcome without real
/// prompts.
@Observable final class PermissionsManager {
    private(set) var music: MusicAccess
    private(set) var library = MusicLibraryAccess.unknown
    private(set) var photos: PhotoAccess
    private(set) var isRequestingMusic = false
    private(set) var isRequestingPhotos = false

    @ObservationIgnored private let client: any PermissionsClient

    init(client: any PermissionsClient = LivePermissionsClient()) {
        self.client = client
        music = client.musicStatus()
        photos = client.photoStatus()
    }

    /// Re-reads every status. Call it when the app becomes active, since the
    /// user may have changed something in Settings.
    func refresh() async {
        music = client.musicStatus()
        photos = client.photoStatus()
        library = music == .authorized ? await client.libraryAccess() : .unknown
    }

    /// Shows the Apple Music prompt (only the first time; after that the
    /// system returns the saved answer straight away).
    func requestMusic() async {
        guard !isRequestingMusic else { return }
        isRequestingMusic = true
        defer { isRequestingMusic = false }
        music = await client.requestMusic()
        if music == .authorized {
            library = await client.libraryAccess()
        }
    }

    /// Shows the Photos prompt. Caffy only reads photos, but `.readWrite`
    /// is the level that includes reading.
    func requestPhotos() async {
        guard !isRequestingPhotos else { return }
        isRequestingPhotos = true
        defer { isRequestingPhotos = false }
        photos = await client.requestPhotos()
    }

    /// Caffy's page in the Settings app.
    static let settingsURL = URL(string: UIApplication.openSettingsURLString)!

    /// The manager the app starts with. DEBUG builds accept
    /// `-fakePermissions <preset>` to try each outcome in the simulator,
    /// which has no Apple Music. See `PreviewPermissionsClient.preset(named:)`.
    static func forLaunch() -> PermissionsManager {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "fakePermissions"),
           let fake = PreviewPermissionsClient.preset(named: name) {
            return PermissionsManager(client: fake)
        }
        #endif
        return PermissionsManager()
    }
}
