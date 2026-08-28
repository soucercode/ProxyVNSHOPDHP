import Foundation

enum PatchAssetLoader {
    static func url(for definition: LocalPatchDefinition, bundle: Bundle = .main) -> URL? {
        // Tìm file trong gốc bundle (không cần thư mục con)
        if let url = bundle.url(forResource: definition.resourceName, withExtension: "3105") {
            return url
        }
        return nil
    }

    static func exists(for definition: LocalPatchDefinition, bundle: Bundle = .main) -> Bool {
        url(for: definition, bundle: bundle) != nil
    }

    static func availableFeatures(for game: LocalGameVariant, bundle: Bundle = .main) -> Set<LocalPatchFeature> {
        Set(LocalPatchFeature.allCases.filter { feature in
            guard let definition = LocalPatchDefinitions.definition(for: feature, game: game) else {
                return false
            }
            return exists(for: definition, bundle: bundle)
        })
    }
}
