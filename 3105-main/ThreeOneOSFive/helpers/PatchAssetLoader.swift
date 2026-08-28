import Foundation

enum PatchAssetLoader {
    static func loadPatchData(for definition: LocalPatchDefinition) -> Data? {
        guard let game = LocalGameVariant(rawValue: definition.game.rawValue) else { return nil }
        return EmbeddedPatchLoader.data(for: definition.feature, game: game)
    }

    static func exists(for definition: LocalPatchDefinition) -> Bool {
        return loadPatchData(for: definition) != nil
    }

    static func availableFeatures(for game: LocalGameVariant) -> Set<LocalPatchFeature> {
        Set(LocalPatchFeature.allCases.filter { feature in
            guard let definition = LocalPatchDefinitions.definition(for: feature, game: game) else {
                return false
            }
            return exists(for: definition)
        })
    }
}
