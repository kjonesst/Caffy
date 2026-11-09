import SwiftUI

/// Step 6: add photos. Full and Limited access both count as success, and a
/// "no" can still continue.
struct PhotosStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.openURL) private var openURL

    private typealias Copy = OnboardingCopy.Photos

    var body: some View {
        OnboardingLayout(
            title: Copy.title,
            message: Copy.message,
            primary: OnboardingAction(title: Copy.button, systemImage: "arrow.right", action: continueTapped),
            secondary: secondary
        ) {
            OnboardingSymbolVisual(symbol: "photo.on.rectangle.angled", badge: status?.tone)
        } content: {
            if let status {
                OnboardingStatusCard(status: status)
                    .transition(.opacity)
            }
        }
        .animation(OnboardingStyle.statusAnimation, value: permissions.photos)
    }

    private func continueTapped() {
        if permissions.photos == .notDetermined {
            Task { await permissions.requestPhotos() }
        } else {
            model.next()
        }
    }

    private var status: OnboardingStatus? {
        switch permissions.photos {
        case .notDetermined:
            nil
        case .full:
            OnboardingStatus(tone: .positive, symbol: "checkmark.circle.fill", title: Copy.fullTitle, detail: Copy.fullDetail)
        case .limited:
            OnboardingStatus(tone: .positive, symbol: "checkmark.circle.fill", title: Copy.limitedTitle, detail: Copy.limitedDetail)
        case .denied:
            OnboardingStatus(tone: .caution, symbol: "photo", title: Copy.deniedTitle, detail: Copy.deniedDetail)
        case .restricted:
            OnboardingStatus(tone: .caution, symbol: "lock", title: Copy.restrictedTitle, detail: Copy.restrictedDetail)
        }
    }

    /// Settings is where Limited selections change and where a "no" can be
    /// turned into a "yes". Restricted access can't be changed there.
    private var secondary: OnboardingAction? {
        let title: LocalizedStringResource
        switch permissions.photos {
        case .limited: title = Copy.changeSelection
        case .denied: title = OnboardingCopy.Common.openSettings
        default: return nil
        }
        return OnboardingAction(title: title, systemImage: "gear", hint: OnboardingCopy.Common.openSettingsHint) {
            openURL(PermissionsManager.settingsURL)
        }
    }
}

// MARK: - Previews

private func photosPreview(_ client: PreviewPermissionsClient) -> some View {
    OnboardingView(startingAt: .photos)
        .environment(PermissionsManager(client: client))
}

#Preview("Not asked yet", traits: .onboarding) {
    photosPreview(.notAsked)
}

#Preview("Full access", traits: .onboarding) {
    photosPreview(.photosFull)
}

#Preview("Limited access", traits: .onboarding) {
    photosPreview(.photosLimited)
}

#Preview("Denied", traits: .onboarding) {
    photosPreview(.photosDenied)
}

#Preview("Restricted", traits: .onboarding) {
    photosPreview(.photosRestricted)
}

#Preview("Limited, dark, largest text", traits: .onboarding) {
    photosPreview(.photosLimited)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
