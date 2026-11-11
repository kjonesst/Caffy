import SwiftUI

/// One of the user's photos, filling whatever frame it's given.
///
/// Shows `PhotoPlaceholder` until the photo loads, and keeps showing it when
/// there's no photo to load: sample data, no photo access, or a photo that's
/// gone from the library.
struct PhotoThumbnail: View {
    /// The PhotoKit identifier of the photo to show.
    let assetIdentifier: String?
    /// Picks the placeholder's tone.
    let seed: String
    /// About how big the photo is drawn, in points, so it loads sharp enough
    /// without loading more pixels than needed.
    let size: CGSize
    var showsIcon = true

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        PhotoPlaceholder(seed: seed, showsIcon: showsIcon && image == nil)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            // Reloads when the photo or its size changes, and stops if the
            // view goes away first.
            .task(id: "\(assetIdentifier ?? "")|\(Int(size.width))x\(Int(size.height))") {
                let pixels = CGSize(width: size.width * displayScale, height: size.height * displayScale)
                let loaded = await PhotoThumbnailLoader.shared.image(for: assetIdentifier, pixelSize: pixels)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    image = loaded
                }
            }
    }
}

#Preview {
    // Sample ids never load, so this shows the placeholder.
    PhotoThumbnail(assetIdentifier: "sample-m0001-p1", seed: "Bondi Beach", size: CGSize(width: 240, height: 180))
        .frame(width: 240, height: 180)
}
