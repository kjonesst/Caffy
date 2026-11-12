import SwiftData
import SwiftUI

/// Gives Xcode previews an in-memory database filled with sample data.
///
/// A `PreviewModifier` builds its context once and shares it across previews.
/// Use it by writing `#Preview(traits: .sampleData) { ... }`.
struct SampleDataPreview: PreviewModifier {
    static func makeSharedContext() async throws -> ModelContainer {
        Theme.registerFonts()
        let container = try CaffyStore.makeContainer(inMemory: true)
        try await SampleData.insert(into: container.mainContext)
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sampleData: Self { .modifier(SampleDataPreview()) }
}
