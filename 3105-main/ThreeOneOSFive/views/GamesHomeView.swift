import SwiftUI
import UIKit

struct GamesHomeView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var store = PatchProjectStore()
    @State private var games: [RemoteGameSummary] = []
    @State private var isLoadingGames = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                TechBackground()

                ScrollView {
                    deviceInfoCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(games) { game in
                            NavigationLink {
                                // SỬA: Dùng GameDemoView thay vì GamePatchesView
                                GameDemoView(
                                    title: game.name,
                                    imageName: game.iconPath?.components(separatedBy: "/").last ?? "app.fill",
                                    bundleID: game.bundleID,
                                    state: ProxyDemoState()
                                )
                            } label: {
                                GameCardView(
                                    title: game.name,
                                    subtitle: game.bundleID.isEmpty ? " " : game.bundleID,
                                    bannerColor: Color(hex: game.bannerColor) ?? AppTheme.accent,
                                    iconURL: game.iconURL,
                                    systemIconName: "app.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)

                    if games.isEmpty && !isLoadingGames {
                        Text(language.text("patch.no_games_yet"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                    }
                }
            }
            .navigationTitle(language.text("tab.home"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(language.text("tab.settings"))
                }
            }
            .refreshable { await loadGames() }
            .task { await loadGames() }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }

    private func loadGames() async {
        isLoadingGames = true
        if let fetched = try? await PatchHubService.fetchGames() {
            games = fetched
        }
        isLoadingGames = false
    }

    private var deviceInfoCard: some View {
        VStack(spacing: 12) {
            deviceInfoRow(icon: "apple.logo", iconColor: .purple, label: "iOS", value: shortOSVersion)
            deviceInfoRow(icon: "iphone", iconColor: AppTheme.techGlow, label: language.text("common.device"), value: AppInfo.hardwareDisplayName)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .techCard()
    }

    private func deviceInfoRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var shortOSVersion: String {
        let version = AppInfo.osVersion
        if version.hasSuffix(".0") {
            return String(version.dropLast(2))
        }
        return version
    }
}

struct GameCardView: View {
    let title: String
    let subtitle: String
    let bannerColor: Color
    let iconURL: URL?
    let systemIconName: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                bannerColor
                iconView
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
            }
            .frame(height: 88)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppTheme.techCardFill)
        }
        .background(Color.black.opacity(0.001))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.techCardStroke, lineWidth: 1)
        )
        .shadow(color: AppTheme.techGlow.opacity(0.10), radius: 10, y: 0)
    }

    @ViewBuilder
    private var iconView: some View {
        if let iconURL {
            CachedAsyncImage(url: iconURL) {
                placeholderIcon
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: systemIconName)
            .resizable()
            .scaledToFit()
            .padding(13)
            .foregroundStyle(.white)
    }
}

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = RemoteImageCache.cachedImage(for: url) {
                uiImage = cached
            }
            if let fresh = await RemoteImageCache.fetchAndCache(url) {
                uiImage = fresh
            }
        }
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
