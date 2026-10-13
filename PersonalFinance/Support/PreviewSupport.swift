import SwiftUI
import SwiftData
import FinancePersistence

// Not wrapped in #if DEBUG: #Preview blocks reference these traits and are
// still type-checked in Release builds.

/// In-memory store filled with `PreviewFixtures`. Previews never read the
/// user's real database.
struct SampleDataPreview: PreviewModifier {
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try ModelContainerFactory.makeContainer(at: .inMemory)
        try PreviewFixtures.populate(ModelContext(container))
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modelContainer(context)
            .environment(AppContainer(modelContainer: context, location: .inMemory))
    }
}

/// In-memory store with only the default categories: what a new user sees.
struct EmptyStorePreview: PreviewModifier {
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try ModelContainerFactory.makeContainer(at: .inMemory)
        try DefaultCategorySeeder.seedIfNeeded(in: ModelContext(container))
        return container
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modelContainer(context)
            .environment(AppContainer(modelContainer: context, location: .inMemory))
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor static var sampleData: Self = .modifier(SampleDataPreview())
    @MainActor static var emptyStore: Self = .modifier(EmptyStorePreview())
}
