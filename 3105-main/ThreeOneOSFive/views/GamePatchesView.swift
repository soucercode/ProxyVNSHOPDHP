import SwiftUI
import UIKit

struct GamePatchesView: View {
    @Environment(\.appLanguage) private var language
    let game: RemoteGameSummary
    @ObservedObject var store: PatchProjectStore

    @State private var busyFeature: LocalPatchFeature?
    @State private var enabled: [LocalPatchFeature: Bool] = [:]
    @State private var showUnsupported = false
    @State private var toast: ToastMessage?
    @State private var availableFeatures: Set<LocalPatchFeature> = []

    private var localGame: LocalGameVariant? {
        LocalGameVariant(rawValue: game.bundleID)
    }

    var body: some View {
        ZStack {
            TechBackground()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    menuCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(localGame?.displayName ?? game.name)
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .task { refreshAvailability() }
        .alert("Chưa sẵn sàng", isPresented: $showUnsupported) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Chức năng này đang bảo trì vì chưa có file patch tương ứng.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            gameIconView
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Text(localGame?.displayName ?? game.name)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)

            Text(game.bundleID)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                openGame()
            } label: {
                Label("MỞ GAME", systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 24)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var gameIconView: some View {
        if let localGame {
            Image(localGame.iconAssetName)
                .resizable()
                .scaledToFit()
                .padding(2)
                .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if let url = game.iconURL {
            CachedAsyncImage(url: url) {
                Image(systemName: "gamecontroller.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(24)
                    .foregroundStyle(.white)
            }
        } else {
            Image(systemName: "gamecontroller.fill")
                .resizable()
                .scaledToFit()
                .padding(24)
                .foregroundStyle(.white)
        }
    }

    private var menuCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Proxy", systemImage: "bolt.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.techGlow)
                Spacer()
            }
            .padding(.horizontal, 6)

            ForEach(LocalPatchFeature.allCases) { feature in
                featureRow(feature)
            }
        }
        .padding(10)
        .techCard()
    }

    private func featureRow(_ feature: LocalPatchFeature) -> some View {
        let available = isAvailable(feature)
        let isBusy = busyFeature == feature

        return HStack(spacing: 14) {
            Image(systemName: iconName(for: feature))
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(iconColor(for: feature).opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.rawValue)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                // Only the availability state is shown. No payload filename/path is exposed.
                Text(available ? "Sẵn sàng" : "Đang bảo trì")
                    .font(.caption)
                    .foregroundStyle(available ? Color.secondary : Color.orange)
            }

            Spacer()

            if isBusy {
                ProgressView()
            } else {
                Toggle("", isOn: Binding(
                    get: { enabled[feature] ?? false },
                    set: { value in
                        guard available else {
                            showUnsupported = true
                            return
                        }
                        setFeature(feature, value)
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.techGlow)
                .disabled(!available)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func isAvailable(_ feature: LocalPatchFeature) -> Bool {
        availableFeatures.contains(feature)
    }

    private func refreshAvailability() {
        guard let localGame else {
            availableFeatures = []
            return
        }
        availableFeatures = PatchAssetLoader.availableFeatures(for: localGame)

        // A feature is never considered available merely because it exists in the enum.
        // It must have its exact game-specific resource in the app bundle.
        for feature in LocalPatchFeature.allCases where !availableFeatures.contains(feature) {
            enabled[feature] = false
        }
    }

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
            // Four-second UI apply simulation. It writes only to this app's own demo workspace.
            try? await Task.sleep(nanoseconds: 4_000_000_000)

            if value {
                do {
                    _ = try DevicePatchService.applyBundledDemoPatch(
                        resourceName: definition.resourceName + ".3105",
                        featureName: feature.rawValue
                    )
                    enabled[feature] = true
                    toast = ToastMessage(text: "\(feature.rawValue) • Ready / Sẵn sàng")
                } catch {
                    enabled[feature] = false
                    toast = ToastMessage(text: "Demo apply failed / Áp dụng thử nghiệm thất bại")
                }
            } else {
                enabled[feature] = false
            }

            busyFeature = nil
        }
    }

    private func openGame() {
        guard let url = URL(string: "\(game.bundleID)://") else { return }
        UIApplication.shared.open(url)
    }

    private func iconName(for feature: LocalPatchFeature) -> String {
        switch feature {
        case .aimBody: return "bolt.fill"
        case .aimNeckV1: return "bolt.fill"
        case .aimNeckV2: return "bolt.fill"
        case .magicV4: return "bolt.fill"
        case .aimDrag: return "bolt.fill"
        case .location: return "location.fill"
        }
    }

    private func iconColor(for feature: LocalPatchFeature) -> Color {
        switch feature {
        case .aimBody: return .orange
        case .aimNeckV1: return .pink
        case .aimNeckV2: return .cyan
        case .magicV4: return .green
        case .aimDrag: return .purple
        case .location: return .gray
        }
    }
}
