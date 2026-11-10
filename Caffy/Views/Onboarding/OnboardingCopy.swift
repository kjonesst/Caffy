import Foundation

/// One point in a list: an SF Symbol, a short title, and one line of detail.
struct OnboardingPointContent: Identifiable {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var id: String { symbol }
}

/// Every word the onboarding flow shows, in one place so it's easy to edit.
///
/// They're `LocalizedStringResource`s, so Xcode can pull them into a string
/// catalog for translation later.
enum OnboardingCopy {
    enum Common {
        static let back: LocalizedStringResource = "Back"
        static let skip: LocalizedStringResource = "Skip"
        static let skipHint: LocalizedStringResource = "Goes straight to connecting Apple Music"
        static let next: LocalizedStringResource = "Continue"
        static let openSettings: LocalizedStringResource = "Open Settings"
        static let openSettingsHint: LocalizedStringResource = "Opens Caffy's page in the Settings app"

        static func progress(_ step: Int, of total: Int) -> LocalizedStringResource {
            "Step \(step) of \(total)"
        }
    }

    enum Welcome {
        /// Lowercase, like the wordmark on Home and in the launch splash, which glides into it.
        static let appName: LocalizedStringResource = "caffy"
        static let headline: LocalizedStringResource = "Your photos have places. Your places have a soundtrack."
        static let button: LocalizedStringResource = "Get started"
    }

    enum Problem {
        static let title: LocalizedStringResource = "You remember the trip. You forget what you were listening to."
        static let message: LocalizedStringResource = "Your photos know where you were and when. Your music knows what you played. They live in separate apps, so the soundtrack to a summer, a move or a road trip quietly slips away."
        static let photosLabel: LocalizedStringResource = "Photos"
        static let photosCaption: LocalizedStringResource = "Lisbon · Aug"
        static let musicLabel: LocalizedStringResource = "Music"
        static let musicCaption: LocalizedStringResource = "Recently played"
        static let visualLabel: LocalizedStringResource = "Your photos and your music, in two separate apps that don't know about each other."
    }

    enum HowItWorks {
        static let title: LocalizedStringResource = "Caffy makes the playlists for you"
        static let message: LocalizedStringResource = "You live, take photos and listen. Caffy does the rest."
        static let points = [
            OnboardingPointContent(
                symbol: "music.note",
                title: "Connect Apple Music",
                detail: "Caffy sees what you've been listening to."
            ),
            OnboardingPointContent(
                symbol: "mappin.and.ellipse",
                title: "Matched to your moments",
                detail: "Caffy pairs your music with where and when your photos were taken."
            ),
            OnboardingPointContent(
                symbol: "music.note.list",
                title: "Playlists in your library",
                detail: "Each one appears in Apple Music and keeps updating as life goes on."
            )
        ]
        static let footnote: LocalizedStringResource = "There's no player in Caffy. Listen where you already do, in Apple Music."
    }

    enum Privacy {
        static let title: LocalizedStringResource = "Private by design"
        static let message: LocalizedStringResource = "Before Caffy asks for anything, here's what it promises."
        static let points = [
            OnboardingPointContent(
                symbol: "person.crop.circle.badge.xmark",
                title: "No account",
                detail: "No sign-up, no email, no password."
            ),
            OnboardingPointContent(
                symbol: "nosign",
                title: "No ads, no tracking",
                detail: "Caffy is free, and nothing you do is measured or sold."
            ),
            OnboardingPointContent(
                symbol: "chevron.left.forwardslash.chevron.right",
                title: "Open source",
                detail: "Anyone can read the code and check how it works."
            ),
            OnboardingPointContent(
                symbol: "lock.iphone",
                title: "Photos stay on your device",
                detail: "Caffy reads where and when they were taken. Nothing is uploaded."
            )
        ]
    }

    enum Music {
        static let title: LocalizedStringResource = "Connect Apple Music"
        static let message: LocalizedStringResource = "Caffy looks at what you listen to and when, so it can match songs to your photos. Then it builds the playlists right in your library."
        static let button: LocalizedStringResource = "Continue"

        static let connectedTitle: LocalizedStringResource = "Apple Music is connected"
        static let connectedDetail: LocalizedStringResource = "Caffy can see your listening and add playlists to your library."
        static let alreadyConnectedDetail: LocalizedStringResource = "You've connected before, so there's nothing to do here."

        static let noSubscriptionTitle: LocalizedStringResource = "No Apple Music subscription"
        static let noSubscriptionDetail: LocalizedStringResource = "Caffy can still match your music with your photos, and you'll see every era here. Adding playlists to your library needs a subscription."
        static let cannotSubscribeDetail: LocalizedStringResource = "Caffy can still match your music with your photos, and you'll see every era here. Adding playlists to your library needs Apple Music, which isn't available on this account."

        static let syncOffTitle: LocalizedStringResource = "Turn on Sync Library"
        static let syncOffDetail: LocalizedStringResource = "Caffy adds playlists to your library, so Sync Library needs to be on. You'll find it in Settings › Apps › Music."

        static let deniedTitle: LocalizedStringResource = "Apple Music is off for Caffy"
        static let deniedDetail: LocalizedStringResource = "That's okay. Caffy can't build playlists without it, but you can turn it on anytime in Settings."

        static let restrictedTitle: LocalizedStringResource = "Apple Music is restricted"
        static let restrictedDetail: LocalizedStringResource = "This iPhone doesn't let apps use Apple Music, for example because of Screen Time. Caffy will still open, but can't build playlists."
    }

    enum Photos {
        static let title: LocalizedStringResource = "Add your photos"
        static let message: LocalizedStringResource = "Caffy uses where and when each photo was taken to find your moments. It never asks for your location, and your photos stay on your iPhone."
        static let button: LocalizedStringResource = "Continue"

        static let fullTitle: LocalizedStringResource = "Photos connected"
        static let fullDetail: LocalizedStringResource = "Caffy can see where and when your photos were taken."

        static let limitedTitle: LocalizedStringResource = "You chose which photos Caffy sees"
        static let limitedDetail: LocalizedStringResource = "Caffy will only use those. You can change your selection anytime in Settings."
        static let changeSelection: LocalizedStringResource = "Change in Settings"

        static let deniedTitle: LocalizedStringResource = "Photos are off for Caffy"
        static let deniedDetail: LocalizedStringResource = "Caffy needs your photos' places and dates to find moments. You can turn it on anytime in Settings."

        static let restrictedTitle: LocalizedStringResource = "Photos are restricted"
        static let restrictedDetail: LocalizedStringResource = "This iPhone doesn't let apps see photos. Caffy will still open, but can't find moments."
    }

    enum Ready {
        static let button: LocalizedStringResource = "Open Caffy"

        // Both granted.
        static let allTitle: LocalizedStringResource = "You're all set"
        static let allMessage: LocalizedStringResource = "Caffy is matching your photos and music now. Your first playlist will appear in Apple Music when it's ready."
        static let building: LocalizedStringResource = "Building your first collage"
        static let buildingStages: [LocalizedStringResource] = [
            "Reading places and dates…",
            "Matching songs to moments…",
            "Laying out the prints…"
        ]

        // Only Apple Music.
        static let musicOnlyTitle: LocalizedStringResource = "Almost there"
        static let musicOnlyMessage: LocalizedStringResource = "Caffy can see your music, but needs your photos to find moments. You can add them anytime in Settings."

        // Only Photos.
        static let photosOnlyTitle: LocalizedStringResource = "Almost there"
        static let photosOnlyMessage: LocalizedStringResource = "Caffy can find your moments, but needs Apple Music to match songs and build playlists. You can connect it anytime in Settings."

        // Neither.
        static let noneTitle: LocalizedStringResource = "Have a look around"
        static let noneMessage: LocalizedStringResource = "Caffy needs Apple Music and your photos to build playlists. Turn them on anytime in Settings, and Caffy will pick up from there."

        // The checklist.
        static let musicConnected: LocalizedStringResource = "Apple Music connected"
        static let musicNeedsSubscription: LocalizedStringResource = "Apple Music connected · playlists need a subscription"
        static let musicSyncOff: LocalizedStringResource = "Apple Music connected · turn on Sync Library"
        static let musicOff: LocalizedStringResource = "Apple Music not connected"
        static let photosAll: LocalizedStringResource = "All photos"
        static let photosSelected: LocalizedStringResource = "Selected photos"
        static let photosOff: LocalizedStringResource = "Photos not added"
        static let itemOn: LocalizedStringResource = "On"
        static let itemNeedsAttention: LocalizedStringResource = "Needs attention"
        static let itemOff: LocalizedStringResource = "Off"
    }
}
