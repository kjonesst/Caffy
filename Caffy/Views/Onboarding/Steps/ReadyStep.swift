import SwiftUI

/// Step 7: confirms what was set up. With both permissions it shows Caffy
/// "building" the first collage (mock content for now); otherwise it explains
/// what's missing and where to turn it on. No notification prompt here: that
/// comes after the first playlist exists.
struct ReadyStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(PermissionsManager.self) private var permissions
    @Environment(\.openURL) private var openURL

    private typealias Copy = OnboardingCopy.Ready

    private enum Outcome {
        case everything
        case musicOnly
        case photosOnly
        case nothing
    }

    private var outcome: Outcome {
        switch (permissions.music == .authorized, permissions.photos.isGranted) {
        case (true, true): .everything
        case (true, false): .musicOnly
        case (false, true): .photosOnly
        case (false, false): .nothing
        }
    }

    var body: some View {
        OnboardingLayout(
            title: title,
            message: message,
            visualMinHeight: outcome == .everything ? OnboardingStyle.heroMinHeight : OnboardingStyle.visualMinHeight,
            primary: OnboardingAction(title: Copy.button, systemImage: "arrow.right", action: model.finish),
            secondary: secondary
        ) {
            if outcome == .everything {
                BuildingCollageVisual()
            } else {
                OnboardingSymbolVisual(symbol: "checklist", badge: .caution)
            }
        } content: {
            ReadyChecklist(items: checklist)
        }
    }

    private var title: LocalizedStringResource {
        switch outcome {
        case .everything: Copy.allTitle
        case .musicOnly: Copy.musicOnlyTitle
        case .photosOnly: Copy.photosOnlyTitle
        case .nothing: Copy.noneTitle
        }
    }

    private var message: LocalizedStringResource {
        switch outcome {
        case .everything: Copy.allMessage
        case .musicOnly: Copy.musicOnlyMessage
        case .photosOnly: Copy.photosOnlyMessage
        case .nothing: Copy.noneMessage
        }
    }

    /// Settings, for whatever is still off.
    private var secondary: OnboardingAction? {
        guard outcome != .everything else { return nil }
        return OnboardingAction(
            title: OnboardingCopy.Common.openSettings,
            systemImage: "gear",
            hint: OnboardingCopy.Common.openSettingsHint
        ) {
            openURL(PermissionsManager.settingsURL)
        }
    }

    private var checklist: [ReadyChecklist.Item] {
        let music: ReadyChecklist.Item = switch (permissions.music, permissions.library) {
        case (.authorized, .needsSubscription):
            .init(id: "music", tone: .neutral, label: Copy.musicNeedsSubscription)
        case (.authorized, .syncLibraryOff):
            .init(id: "music", tone: .neutral, label: Copy.musicSyncOff)
        case (.authorized, _):
            .init(id: "music", tone: .positive, label: Copy.musicConnected)
        default:
            .init(id: "music", tone: nil, label: Copy.musicOff)
        }

        let photos: ReadyChecklist.Item = switch permissions.photos {
        case .full: .init(id: "photos", tone: .positive, label: Copy.photosAll)
        case .limited: .init(id: "photos", tone: .positive, label: Copy.photosSelected)
        default: .init(id: "photos", tone: nil, label: Copy.photosOff)
        }

        return [music, photos]
    }
}

// MARK: - Building state

/// The memory burst, with a line underneath stepping through what Caffy is
/// doing. The stages are mock text until the real matching exists.
private struct BuildingCollageVisual: View {
    @State private var stage = 0

    @Environment(\.colorScheme) private var colorScheme

    private typealias Copy = OnboardingCopy.Ready
    private static let stageDuration = 1.8

    var body: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)

        VStack(spacing: 10) {
            // Placeholder art until real photos and playlists exist.
            MemoryBurst(replaysOnTap: false)

            VStack(spacing: 6) {
                Text(Copy.building)
                    .font(Theme.mono(12, medium: true))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(palette.title)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    // A cross-fade between stages, which is calm enough to
                    // keep under Reduce Motion.
                    Text(Copy.buildingStages[stage])
                        .id(stage)
                        .transition(.opacity)
                }
                .font(Theme.mono(12))
                .foregroundStyle(palette.body)
                .animation(.easeInOut(duration: 0.4), value: stage)
            }
            .padding(.bottom, 8)
        }
        // VoiceOver hears one steady description, not every stage change.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Copy.building))
        .task {
            for next in Copy.buildingStages.indices.dropFirst() {
                try? await Task.sleep(for: .seconds(Self.stageDuration))
                guard !Task.isCancelled else { return }
                stage = next
            }
        }
    }
}

// MARK: - Checklist

/// What's on and what isn't, one row per permission.
private struct ReadyChecklist: View {
    struct Item: Identifiable {
        let id: String
        /// `nil` means off.
        let tone: OnboardingTone?
        let label: LocalizedStringResource
    }

    let items: [Item]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = OnboardingStyle.palette(for: colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol(for: item.tone))
                        .foregroundStyle(item.tone?.color(in: palette) ?? palette.body)
                        .accessibilityHidden(true)
                    Text(item.label)
                        .foregroundStyle(item.tone == nil ? palette.body : palette.title)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.display(OnboardingStyle.pointDetailSize + 1, weight: .medium, relativeTo: .body))
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(value(for: item.tone)))
            }
        }
        .padding(OnboardingStyle.statusCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: .rect(cornerRadius: OnboardingStyle.statusCardCorner))
    }

    private func symbol(for tone: OnboardingTone?) -> String {
        switch tone {
        case .positive: "checkmark.circle.fill"
        case .neutral, .caution: "exclamationmark.circle.fill"
        case nil: "circle"
        }
    }

    private func value(for tone: OnboardingTone?) -> LocalizedStringResource {
        switch tone {
        case .positive: OnboardingCopy.Ready.itemOn
        case .neutral, .caution: OnboardingCopy.Ready.itemNeedsAttention
        case nil: OnboardingCopy.Ready.itemOff
        }
    }
}

// MARK: - Previews

private func readyPreview(_ client: PreviewPermissionsClient) -> some View {
    OnboardingView(startingAt: .ready)
        .environment(PermissionsManager(client: client))
}

#Preview("Everything", traits: .onboarding) {
    readyPreview(.allGranted)
}

#Preview("Everything, selected photos", traits: .onboarding) {
    readyPreview(.photosLimited)
}

#Preview("Everything, no subscription", traits: .onboarding) {
    readyPreview(PreviewPermissionsClient(music: .authorized, library: .needsSubscription(canSubscribe: true), photos: .full))
}

#Preview("Music only", traits: .onboarding) {
    readyPreview(.photosDenied)
}

#Preview("Photos only", traits: .onboarding) {
    readyPreview(.photosOnly)
}

#Preview("Nothing", traits: .onboarding) {
    readyPreview(.nothingGranted)
}

#Preview("Everything, dark, largest text", traits: .onboarding) {
    readyPreview(.allGranted)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
