import SwiftUI

struct GamePatchesView: View {
    @Environment(\.appLanguage) private var language
    let game: RemoteGameSummary
    @ObservedObject var store: PatchProjectStore

    @State private var isSyncing = false
    @State private var projectStates: [UUID: Bool] = [:]
    @State private var togglingProjectID: UUID?
    @State private var toast: ToastMessage?
    @AppStorage("patch.importedOnlineIDs") private var importedOnlineIDsRaw = ""
    @AppStorage("patch.gameAssignments") private var gameAssignmentsRaw = "{}"
    @AppStorage("patch.remoteToLocalMap") private var remoteToLocalMapRaw = "{}"

    private var importedOnlineIDs: Set<String> {
        Set(importedOnlineIDsRaw.split(separator: ",").map(String.init))
    }

    private var gameAssignments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(gameAssignmentsRaw.utf8))) ?? [:]
    }

    /// Server patch id -> local packageID, so a patch removed on the server can be traced back
    /// to the local file it downloaded into and deleted, instead of only ever growing the library.
    private var remoteToLocalMap: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(remoteToLocalMapRaw.utf8))) ?? [:]
    }

    private var items: [PatchLibraryItem] {
        let assignments = gameAssignments
        return store.items.filter { assignments[$0.id.uuidString] == game.id }
    }

    var body: some View {
        ZStack {
            TechBackground()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    menuCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable {
                await sync()
                await loadProjectStates()
            }
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSyncing {
                    ProgressView()
                }
            }
        }
        .task {
            await sync()
            await loadProjectStates()
        }
        .sheet(item: $store.passwordRequest, onDismiss: store.cancelUnlock) { _ in
            PatchUnlockView(store: store)
        }
        .alert(item: $store.alert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
        .toast($toast)
    }

    /// The single bordered box holding every patch for this game as a switch row, matching the
    /// reference "PROXY MOD MENU" card instead of a plain grouped list.
    private var menuCard: some View {
        VStack(spacing: 0) {
            menuHeader

            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemRow(item, colorIndex: index)
                        if item.id != items.last?.id {
                            Divider()
                                .overlay(Color.white.opacity(0.06))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .techCard()
    }

    private var menuHeader: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(AppTheme.techGlow)
                .frame(width: 3, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            Image(systemName: "bolt.fill")
                .font(.footnote)
                .foregroundStyle(AppTheme.techGlow)
            Text(language.text("patch.menu_title"))
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.primary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if isSyncing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Text(language.text("patch.menu_auto_badge"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.techGlow)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppTheme.techGlow.opacity(0.14), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(AppTheme.techGlow.opacity(0.4), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var header: some View {
        VStack(spacing: 8) {
            gameIconView
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppTheme.techCardStroke, lineWidth: 1)
                )
                .shadow(color: AppTheme.techGlow.opacity(0.18), radius: 14, y: 6)

            Text(game.name)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if !game.bundleID.isEmpty {
                Text(game.bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var gameIconView: some View {
        if let url = game.iconURL {
            CachedAsyncImage(url: url) {
                gameIconPlaceholder
            }
        } else {
            gameIconPlaceholder
        }
    }

    private var gameIconPlaceholder: some View {
        ZStack {
            Color(hex: game.bannerColor) ?? AppTheme.accent
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .padding(20)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem, colorIndex: Int) -> some View {
        if item.isLocked {
            Button { store.requestUnlock(for: item) } label: {
                PatchProjectRow(item: item, language: language)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PatchProjectDetailView(store: store, projectID: item.id)
            } label: {
                toggleRow(item, colorIndex: colorIndex)
            }
        }
    }

    private func toggleRow(_ item: PatchLibraryItem, colorIndex: Int) -> some View {
        let rules = item.project?.rules ?? []
        let toggleableCount = rules.filter(\.canToggle).count
        let rowColor = AppTheme.rowColor(colorIndex)

        return HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundStyle(rowColor)
                .frame(width: 38, height: 38)
                .background(rowColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project?.name ?? language.text("patch.locked_project"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(language.text("patch.rules_count", Int64(rules.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if togglingProjectID == item.id {
                ProgressView()
            } else {
                Toggle("", isOn: projectToggleBinding(for: item))
                    .labelsHidden()
                    .tint(AppTheme.techGlow)
                    .disabled(toggleableCount == 0)
            }
        }
        .padding(.vertical, 10)
    }

    private func projectToggleBinding(for item: PatchLibraryItem) -> Binding<Bool> {
        Binding(
            get: { projectStates[item.id] ?? false },
            set: { setProjectState($0, item: item) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if isSyncing {
                ProgressView()
            } else {
                Image(systemName: "shippingbox")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(AppTheme.accent)
                Text(language.text("patch.empty_title"))
                    .font(.headline)
                Text(language.text("patch.game_empty_message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    /// Downloads only this game's patches from the hub straight into the local library, so
    /// they show up here without any manual tap. Also removes local copies whose server entry
    /// disappeared (deleted on the web, or reassigned to a different game) — a pull-to-refresh
    /// should mirror the server exactly, not just ever grow. The gameId <-> local packageID and
    /// serverID <-> local packageID mappings are recorded locally since the encrypted .3105
    /// format itself carries no game association.
    private func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard let remoteItems = try? await PatchHubService.fetchPatches() else { return }
        let remoteForGame = remoteItems.filter { $0.gameId == game.id }
        let remoteIDsForGame = Set(remoteForGame.map(\.id))

        var imported = importedOnlineIDs
        var assignments = gameAssignments
        var remoteMap = remoteToLocalMap
        var didChange = false

        for (serverID, localID) in remoteMap where assignments[localID] == game.id && !remoteIDsForGame.contains(serverID) {
            if let localUUID = UUID(uuidString: localID),
               let staleItem = store.items.first(where: { $0.id == localUUID }) {
                store.delete(staleItem)
            }
            assignments.removeValue(forKey: localID)
            remoteMap.removeValue(forKey: serverID)
            imported.remove(serverID)
            didChange = true
        }

        let pending = remoteForGame.filter { !imported.contains($0.id) }
        for item in pending {
            do {
                let fileURL = try await PatchHubService.downloadPatch(item)
                let packageIDString: String? = await Task.detached(priority: .utility) {
                    do {
                        let data = try PatchProjectLibrary.readPackage(at: fileURL)
                        let summary = try PatchPackageCodec.inspect(data)
                        _ = try PatchProjectLibrary.save(data: data, projectName: item.name)
                        try? FileManager.default.removeItem(at: fileURL)
                        return summary.packageID.uuidString
                    } catch {
                        return nil
                    }
                }.value
                if let packageIDString {
                    imported.insert(item.id)
                    assignments[packageIDString] = game.id
                    remoteMap[item.id] = packageIDString
                    didChange = true
                }
            } catch {
                continue
            }
        }

        importedOnlineIDsRaw = imported.joined(separator: ",")
        if let encoded = try? JSONEncoder().encode(assignments), let json = String(data: encoded, encoding: .utf8) {
            gameAssignmentsRaw = json
        }
        if let encoded = try? JSONEncoder().encode(remoteMap), let json = String(data: encoded, encoding: .utf8) {
            remoteToLocalMapRaw = json
        }
        if didChange {
            store.reload()
        }
    }

    /// A patch's toggle reflects every toggle-capable rule in it at once: on only when all of
    /// them currently show their replacement active on disk, off otherwise (including "never
    /// applied yet"). Rules without a bundled original are skipped — they simply can't report
    /// or accept an "off" state.
    private func loadProjectStates() async {
        let currentItems = items
        guard !currentItems.isEmpty else { return }
        let states: [UUID: Bool] = await Task.detached(priority: .userInitiated) {
            var result: [UUID: Bool] = [:]
            for item in currentItems {
                let toggleableRules = (item.project?.rules ?? []).filter(\.canToggle)
                guard !toggleableRules.isEmpty else { continue }
                let allOn = toggleableRules.allSatisfy { DevicePatchService.currentRuleState(for: $0) == true }
                result[item.id] = allOn
            }
            return result
        }.value
        projectStates = states
    }

    private func setProjectState(_ isOn: Bool, item: PatchLibraryItem) {
        let toggleableRules = (item.project?.rules ?? []).filter(\.canToggle)
        guard !toggleableRules.isEmpty, togglingProjectID == nil else { return }
        togglingProjectID = item.id
        Task.detached(priority: .userInitiated) {
            var failure: PatchPackageError?
            for rule in toggleableRules {
                do {
                    try DevicePatchService.setRuleState(isOn, rule: rule)
                } catch let error as PatchPackageError {
                    failure = error
                } catch {
                    failure = .applyFailed
                }
            }
            // Re-read actual on-device state rather than assume success, since a partial
            // failure partway through the loop would otherwise show a state that never
            // really landed on every file.
            let actualState = toggleableRules.allSatisfy { DevicePatchService.currentRuleState(for: $0) == true }
            let finalFailure = failure
            await MainActor.run {
                togglingProjectID = nil
                projectStates[item.id] = actualState
                if let finalFailure {
                    store.alert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: finalFailure.localizationKey,
                        messageArgument: finalFailure.localizationArgument
                    )
                } else if actualState == isOn {
                    let name = item.project?.name ?? language.text("patch.locked_project")
                    let key = isOn ? "patch.toggle_on_success" : "patch.toggle_off_success"
                    toast = ToastMessage(text: language.text(key, name))
                }
            }
        }
    }
}
