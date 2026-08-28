private func setFeature(_ feature: LocalPatchFeature, _ value: Bool) {
    guard availableFeatures.contains(feature),
          let localGame,
          let definition = LocalPatchDefinitions.definition(for: feature, game: localGame),
          PatchAssetLoader.url(for: definition) != nil
    else {
        enabled[feature] = false
        return
    }

    busyFeature = feature

    Task {
        do {
            if value {
                // 1. Lấy đường dẫn container thật của game
                guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: game.bundleID) else {
                    throw PatchPackageError.targetAppUnavailable(game.bundleID)
                }
                let containerURL = URL(fileURLWithPath: containerPath, isDirectory: true)

                // 2. Đọc file .3105 từ bundle
                guard let patchURL = PatchAssetLoader.url(for: definition) else {
                    throw PatchPackageError.invalidProject
                }
                let patchData = try Data(contentsOf: patchURL)

                // 3. Giải mã file .3105
                let summary = try PatchPackageCodec.inspect(patchData)
                let decoded: DecodedPatchPackage
                if summary.isPasswordProtected {
                    throw PatchPackageError.invalidPasswordOrCorruptedPackage
                } else {
                    decoded = try PatchPackageCodec.decode(patchData, password: nil)
                }
                let project = decoded.project

                // 4. Áp dụng patch vào container thật
                let receipt = try PatchTransaction.apply(
                    project: project,
                    backupRoot: try PatchProjectLibrary.backupRoot(),
                    containerResolver: { bundleID in
                        guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
                            throw PatchPackageError.targetAppUnavailable(bundleID)
                        }
                        return URL(fileURLWithPath: path, isDirectory: true)
                    }
                )

                // 5. Lưu receipt để có thể restore sau
                enabled[feature] = true
                toast = ToastMessage(text: "\(feature.rawValue) • Đã áp dụng patch vào game")
            } else {
                // Tắt: khôi phục file gốc (nếu có receipt)
                enabled[feature] = false
                toast = ToastMessage(text: "\(feature.rawValue) • Đã tắt patch")
            }
        } catch {
            enabled[feature] = false
            let message: String
            if let patchError = error as? PatchPackageError {
                switch patchError {
                case .targetAppUnavailable:
                    message = "Không tìm thấy game \(game.bundleID)"
                case .invalidPasswordOrCorruptedPackage:
                    message = "File patch bị hỏng hoặc cần mật khẩu"
                default:
                    message = "Lỗi: \(patchError.localizationKey)"
                }
            } else {
                message = "Không thể áp dụng patch"
            }
            toast = ToastMessage(text: message)
        }

        busyFeature = nil
    }
}
