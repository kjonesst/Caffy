import SwiftUI

/// Step 5: connect Apple Music. Every answer can continue; only the note
/// changes.
struct MusicStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.openURL) private var openURL

    /// Set when Apple Music was already connected on arrival (for example
    /// after a reinstall), so the step confirms and moves on by itself.
    @State private var isAutoAdvancing = false

    private typealias Copy = OnboardingCopy.Music

    var body: some View {
        OnboardingLayout(
            title: Copy.title,
            message: Copy.message,
            primary: OnboardingAction(title: Copy.button, systemImage: "arrow.right", action: continueTapped),
            secondary: secondary
        ) {
            OnboardingSymbolVisual(symbol: "music.note", badge: status?.tone)
        } content: {
            if let status {
                OnboardingStatusCard(status: status)
                    .transition(.opacity)
            }
        }
        .animation(OnboardingStyle.statusAnimation, value: permissions.music)
        .animation(OnboardingStyle.statusAnimation, value: permissions.library)
        .task {
            // Only when arriving forward: going Back from Photos shouldn't
            // bounce straight on again.
            guard model.direction == .forward, permissions.music == .authorized else { return }
            await permissions.refresh()
            guard isReadyForPlaylists else { return }
            isAutoAdvancing = true
            try? await Task.sleep(for: .seconds(OnboardingStyle.autoAdvanceDelay))
            // The task is cancelled if the step goes away first.
            if !Task.isCancelled, model.step == .music { model.next() }
        }
    }

    /// "Continue" asks the first time, and moves on after that, whatever
    /// the answer was.
    private func continueTapped() {
        if permissions.music == .notDetermined {
            Task { await permissions.requestMusic() }
        } else {
            model.next()
        }
    }

    /// Connected, and nothing stands in the way of playlists. An unknown
    /// subscription counts, because without the paid Developer Program the
    /// check always fails.
    private var isReadyForPlaylists: Bool {
        permissions.music == .authorized
            && (permissions.library == .canAddToLibrary || permissions.library == .unknown)
    }

    private var status: OnboardingStatus? {
        switch permissions.music {
        case .notDetermined:
            return nil
        case .denied:
            return OnboardingStatus(tone: .caution, symbol: "music.note", title: Copy.deniedTitle, detail: Copy.deniedDetail)
        case .restricted:
            return OnboardingStatus(tone: .caution, symbol: "lock", title: Copy.restrictedTitle, detail: Copy.restrictedDetail)
        case .authorized:
            switch permissions.library {
            case .unknown, .canAddToLibrary:
                return OnboardingStatus(
                    tone: .positive,
                    symbol: "checkmark.circle.fill",
                    title: Copy.connectedTitle,
                    detail: isAutoAdvancing ? Copy.alreadyConnectedDetail : Copy.connectedDetail
                )
            case .needsSubscription(let canSubscribe):
                return OnboardingStatus(
                    tone: .neutral,
                    symbol: "info.circle.fill",
                    title: Copy.noSubscriptionTitle,
                    detail: canSubscribe ? Copy.noSubscriptionDetail : Copy.cannotSubscribeDetail
                )
            case .syncLibraryOff:
                return OnboardingStatus(tone: .neutral, symbol: "arrow.trianglehead.2.clockwise.rotate.90", title: Copy.syncOffTitle, detail: Copy.syncOffDetail)
            }
        }
    }

    /// "Open Settings" only where the user can fix it there. Restricted
    /// access and Sync Library aren't on Caffy's settings page.
    private var secondary: OnboardingAction? {
        guard permissions.music == .denied else { return nil }
        return OnboardingAction(
            title: OnboardingCopy.Common.openSettings,
            systemImage: "gear",
            hint: OnboardingCopy.Common.openSettingsHint
        ) {
            openURL(PermissionsManager.settingsURL)
        }
    }
}

// MARK: - Previews

private func musicPreview(_ client: PreviewPermissionsClient, arriving: OnboardingModel.Direction = .backward) -> some View {
    // Arriving backward keeps "connected" previews from moving on by themselves.
    OnboardingView(startingAt: .music, arriving: arriving)
        .environment(PermissionsManager(client: client))
}

#Preview("Not asked yet", traits: .onboarding) {
    musicPreview(.notAsked)
}

#Preview("Authorized", traits: .onboarding) {
    musicPreview(.allGranted)
}

#Preview("Already authorized (moves on)", traits: .onboarding) {
    musicPreview(.allGranted, arriving: .forward)
}

#Preview("No subscription", traits: .onboarding) {
    musicPreview(.noSubscription)
}

#Preview("Sync Library off", traits: .onboarding) {
    musicPreview(.syncLibraryOff)
}

#Preview("Denied", traits: .onboarding) {
    musicPreview(.musicDenied)
}

#Preview("Restricted", traits: .onboarding) {
    musicPreview(.musicRestricted)
}

#Preview("Denied, dark, largest text", traits: .onboarding) {
    musicPreview(.musicDenied)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
