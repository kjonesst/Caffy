import MusicKit
import Photos

/// The system calls behind `PermissionsManager`.
///
/// Like `MusicProvider`, this is a protocol so the real MusicKit and Photos
/// calls can be swapped for fixed answers in previews.
protocol PermissionsClient {
    func musicStatus() -> MusicAccess
    func requestMusic() async -> MusicAccess
    func libraryAccess() async -> MusicLibraryAccess
    func photoStatus() -> PhotoAccess
    func requestPhotos() async -> PhotoAccess
}

/// The real thing: MusicKit and the Photos framework. Nothing here asks for
/// location; places come from photo metadata (`PHAsset.location`).
struct LivePermissionsClient: PermissionsClient {
    func musicStatus() -> MusicAccess {
        MusicAccess(MusicAuthorization.currentStatus)
    }

    func requestMusic() async -> MusicAccess {
        MusicAccess(await MusicAuthorization.request())
    }

    func libraryAccess() async -> MusicLibraryAccess {
        // Needs a MusicKit developer token, so it throws until the App ID has
        // the MusicKit service (paid Developer Program).
        guard let subscription = try? await MusicSubscription.current else { return .unknown }
        guard subscription.canPlayCatalogContent else {
            return .needsSubscription(canSubscribe: subscription.canBecomeSubscriber)
        }
        return subscription.hasCloudLibraryEnabled ? .canAddToLibrary : .syncLibraryOff
    }

    func photoStatus() -> PhotoAccess {
        PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestPhotos() async -> PhotoAccess {
        PhotoAccess(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }
}

private extension MusicAccess {
    init(_ status: MusicAuthorization.Status) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .restricted: self = .restricted
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

private extension PhotoAccess {
    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .full
        case .limited: self = .limited
        case .restricted: self = .restricted
        case .denied: self = .denied
        @unknown default: self = .denied
        }
    }
}

/// Fixed answers for previews and the DEBUG `-fakePermissions` argument.
/// A request moves from the "before" status to the "after" one, so tapping
/// Continue in a preview behaves like the real prompt.
struct PreviewPermissionsClient: PermissionsClient {
    var music = MusicAccess.notDetermined
    var musicAfterRequest = MusicAccess.authorized
    var library = MusicLibraryAccess.canAddToLibrary
    var photos = PhotoAccess.notDetermined
    var photosAfterRequest = PhotoAccess.full

    func musicStatus() -> MusicAccess { music }
    func requestMusic() async -> MusicAccess { music == .notDetermined ? musicAfterRequest : music }
    func libraryAccess() async -> MusicLibraryAccess { library }
    func photoStatus() -> PhotoAccess { photos }
    func requestPhotos() async -> PhotoAccess { photos == .notDetermined ? photosAfterRequest : photos }

    // Named outcomes, used by previews and `-fakePermissions <name>`.
    static let notAsked = PreviewPermissionsClient()
    static let allGranted = PreviewPermissionsClient(music: .authorized, photos: .full)
    static let noSubscription = PreviewPermissionsClient(music: .authorized, library: .needsSubscription(canSubscribe: true))
    static let syncLibraryOff = PreviewPermissionsClient(music: .authorized, library: .syncLibraryOff)
    static let subscriptionUnknown = PreviewPermissionsClient(music: .authorized, library: .unknown)
    static let musicDenied = PreviewPermissionsClient(music: .denied)
    static let musicRestricted = PreviewPermissionsClient(music: .restricted)
    static let photosFull = PreviewPermissionsClient(music: .authorized, photos: .full)
    static let photosLimited = PreviewPermissionsClient(music: .authorized, photos: .limited)
    static let photosDenied = PreviewPermissionsClient(music: .authorized, photos: .denied)
    static let photosRestricted = PreviewPermissionsClient(music: .authorized, photos: .restricted)
    static let photosOnly = PreviewPermissionsClient(music: .denied, photos: .full)
    static let nothingGranted = PreviewPermissionsClient(music: .denied, photos: .denied)

    static func preset(named name: String) -> PreviewPermissionsClient? {
        let presets: [String: PreviewPermissionsClient] = [
            "notAsked": notAsked,
            "allGranted": allGranted,
            "noSubscription": noSubscription,
            "syncLibraryOff": syncLibraryOff,
            "subscriptionUnknown": subscriptionUnknown,
            "musicDenied": musicDenied,
            "musicRestricted": musicRestricted,
            "photosFull": photosFull,
            "photosLimited": photosLimited,
            "photosDenied": photosDenied,
            "photosRestricted": photosRestricted,
            "photosOnly": photosOnly,
            "nothingGranted": nothingGranted
        ]
        return presets[name]
    }
}
