import SwiftUI
import UniformTypeIdentifiers

private enum PatchPackagePickerPolicy {
    static let packageType = UTType(filenameExtension: "3105") ?? .data
    static let allowedContentTypes: [UTType] = [packageType, .data]
    static let copiesSelectedDocument = true
}

struct PatchProjectsView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    @State private var showCreate = false
    @State private var showImporter = false

    init(store: PatchProjectStore) {
        self.store = store
#if targetEnvironment(simulator)
        _showCreate = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--simulate-patch-editor")
        )
#endif
    }

    var body: some View {
        List {
            if store.items.isEmpty && !store.isBusy {
                emptyState
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.items) { item in
                    itemRow(item)
                }
                .onDelete { offsets in
                    offsets.map { store.items[$0] }.forEach(store.delete)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { store.reload() }
        .navigationTitle(language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showCreate = true
                    } label: {
                        Label(language.text("patch.new"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label(language.text("patch.import"), systemImage: "square.and.arrow.down")
                    }
                } label: {
                    if store.isBusy {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .disabled(store.isBusy)
                .accessibilityLabel(language.text("patch.add"))
            }
        }
        .sheet(isPresented: $showImporter) {
            FileDocumentPicker(
                allowedContentTypes: PatchPackagePickerPolicy.allowedContentTypes,
                copiesSelectedDocument: PatchPackagePickerPolicy.copiesSelectedDocument,
                allowsMultipleSelection: false,
                onSelection: { result in
                    showImporter = false
                    if case .success(let urls) = result, let url = urls.first {
                        store.importPackage(at: url)
                    }
                },
                onCancel: {
                    showImporter = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCreate) {
            PatchProjectEditorView(
                existingProject: nil,
                passwordIsProtected: false
            ) { project, password in
                store.create(project: project, password: password)
            }
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
    }

    @ViewBuilder
    private func itemRow(_ item: PatchLibraryItem) -> some View {
        if item.isLocked {
            Button { store.requestUnlock(for: item) } label: {
                PatchProjectRow(item: item, language: language)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                PatchProjectDetailView(store: store, projectID: item.id)
            } label: {
                PatchProjectRow(item: item, language: language)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text(language.text("patch.empty_title"))
                .font(.headline)
            Text(language.text("patch.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(language.text("patch.new")) { showCreate = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}

struct PatchProjectRow: View {
    let item: PatchLibraryItem
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isLocked ? "lock.doc.fill" : "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.project?.name ?? language.text("patch.locked_project"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.isLocked
                     ? language.text("patch.tap_to_unlock")
                     : language.text("patch.rules_count", Int64(item.project?.rules.count ?? 0)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.summary.isPasswordProtected {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(language.text("patch.password_protected"))
            }
        }
        .padding(.vertical, 4)
    }
}

struct PatchUnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PatchProjectStore
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(language.text("patch.password"), text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .onSubmit(unlock)
                } footer: {
                    Text(language.text("patch.password_once_message"))
                }
            }
            .navigationTitle(language.text("patch.unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.unlock"), action: unlock)
                        .disabled(password.isEmpty || store.isBusy)
                }
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty else { return }
        store.unlock(password: password)
    }
}

struct PatchProjectDetailView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var store: PatchProjectStore
    let projectID: UUID
    @State private var showEditor = false
    @State private var editingRule: PatchRule?
    @State private var selectedRuleForPatch: PatchRule?
    @State private var showApplyConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var isWorking = false
    @State private var ruleStates: [UUID: Bool] = [:]
    @State private var togglingRuleID: UUID?
    @State private var actionAlert: PatchStoreAlert?
    @State private var toast: ToastMessage?

    private var item: PatchLibraryItem? {
        store.items.first(where: { $0.id == projectID })
    }

    private var receipt: PatchTransactionReceipt? {
        DevicePatchService.latestReceipt(projectID: projectID)
    }

    var body: some View {
        List {
            if let item, let project = item.project {
                Section {
                    ForEach(project.rules) { rule in
                        Button {
                            selectedRuleForPatch = rule
                        } label: {
                            patchFileRow(rule)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(language.text("patch.rules"))
                } footer: {
                    Text("Chọn file để xem thông tin và nhấn Áp dụng patch. Bản demo chỉ ghi vào bộ nhớ riêng của ứng dụng.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TechBackground())
        .navigationTitle(item?.project?.name ?? language.text("patch.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isWorking {
                    ProgressView()
                } else if let item {
                    Menu {
                        Button {
                            showEditor = true
                        } label: {
                            Label(language.text("patch.edit"), systemImage: "pencil")
                        }
                        Button {
                            showApplyConfirmation = true
                        } label: {
                            Label(language.text("patch.apply"), systemImage: "checkmark.shield.fill")
                        }
                        if receipt != nil {
                            Button(role: .destructive) {
                                showRestoreConfirmation = true
                            } label: {
                                Label(language.text("patch.restore"), systemImage: "arrow.uturn.backward.circle")
                            }
                        }
                        ShareLink(item: item.packageURL) {
                            Label(language.text("patch.export"), systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedRuleForPatch) { rule in
            PatchApplyDemoSheet(rule: rule)
        }
        .task { await loadInitialStates() }
        .sheet(isPresented: $showEditor) {
            if let item, let project = item.project {
                PatchProjectEditorView(
                    existingProject: project,
                    passwordIsProtected: item.summary.isPasswordProtected
                ) { updatedProject, _ in
                    store.update(project: updatedProject)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            PatchRuleEditorView(rule: rule) { updatedRule in
                updateRule(updatedRule)
            }
        }
        .confirmationDialog(
            language.text("patch.apply_confirm_title"),
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.apply")) { apply() }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("patch.apply_confirm_message"))
        }
        .confirmationDialog(
            language.text("patch.restore_confirm_title"),
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.restore"), role: .destructive) { restore() }
            Button(language.text("common.cancel"), role: .cancel) {}
        }
        .alert(item: $actionAlert) { alert in
            Alert(
                title: Text(language.text(alert.titleKey)),
                message: Text(alert.message(language: language)),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
        .toast($toast)
    }

    private func patchFileRow(_ rule: PatchRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .font(.title3)
                .foregroundStyle(AppTheme.techGlow)
                .frame(width: 42, height: 42)
                .background(AppTheme.techGlow.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.replacementFilename.isEmpty ? rule.bundleID : rule.replacementFilename)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(rule.relativePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(rule.hasReplacement ? "Sẵn sàng áp dụng patch" : "File đang được bảo trì")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(rule.hasReplacement ? Color.green : Color.orange)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func toggleBinding(for rule: PatchRule) -> Binding<Bool> {
        Binding(
            get: { ruleStates[rule.id] ?? false },
            set: { setRuleState($0, rule: rule) }
        )
    }

    private func loadInitialStates() async {
        guard let project = item?.project else { return }
        let states: [UUID: Bool] = await Task.detached(priority: .userInitiated) {
            var result: [UUID: Bool] = [:]
            for rule in project.rules where rule.canToggle {
                if let state = DevicePatchService.currentRuleState(for: rule) {
                    result[rule.id] = state
                }
            }
            return result
        }.value
        ruleStates = states
    }

    private func setRuleState(_ isOn: Bool, rule: PatchRule) {
        guard rule.canToggle, togglingRuleID == nil else { return }
        togglingRuleID = rule.id
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.setRuleState(isOn, rule: rule)
                await MainActor.run {
                    ruleStates[rule.id] = isOn
                    togglingRuleID = nil
                    let name = rule.replacementFilename.isEmpty ? rule.bundleID : rule.replacementFilename
                    let key = isOn ? "patch.toggle_on_success" : "patch.toggle_off_success"
                    toast = ToastMessage(text: language.text(key, name))
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    togglingRuleID = nil
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    togglingRuleID = nil
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                }
            }
        }
    }

    private func updateRule(_ updatedRule: PatchRule) {
        guard var project = item?.project,
              let index = project.rules.firstIndex(where: { $0.id == updatedRule.id }) else {
            return
        }
        project.rules[index] = updatedRule
        project.updatedAt = Date()
        do {
            try PatchPackageCodec.validate(project)
            store.update(project: project)
        } catch let error as PatchPackageError {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: error.localizationKey,
                messageArgument: error.localizationArgument
            )
        } catch {
            actionAlert = PatchStoreAlert(
                titleKey: "common.failed",
                messageKey: "patch.error.invalid_project"
            )
        }
    }

    private func apply() {
        guard let project = item?.project else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.applied_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.apply")
                }
            }
        }
    }

    private func restore() {
        guard let receipt else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            do {
                try DevicePatchService.restore(receipt: receipt)
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.done", messageKey: "patch.restored_message")
                }
            } catch let error as PatchPackageError {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(
                        titleKey: "common.failed",
                        messageKey: error.localizationKey,
                        messageArgument: error.localizationArgument
                    )
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    actionAlert = PatchStoreAlert(titleKey: "common.failed", messageKey: "patch.error.restore")
                }
            }
        }
    }
}


private struct PatchApplyDemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rule: PatchRule
    @State private var isApplying = false
    @State private var progress = 0.0
    @State private var result: ResultState = .idle

    private enum ResultState {
        case idle, success, failure
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.techGlow)
                    .padding(18)
                    .background(AppTheme.techGlow.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

                Text(rule.replacementFilename.isEmpty ? "Patch file" : rule.replacementFilename)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Label(rule.bundleID, systemImage: "gamecontroller.fill")
                    Label(rule.relativePath, systemImage: "folder.fill")
                        .lineLimit(2)
                    Label("Bản demo an toàn: dữ liệu được ghi trong bộ nhớ riêng của app", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                if isApplying {
                    VStack(spacing: 10) {
                        ProgressView(value: progress)
                        Text("Đang áp dụng patch…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    switch result {
                    case .success:
                        Label("Áp dụng patch thành công", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure:
                        Label("Áp dụng patch thất bại", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    case .idle:
                        EmptyView()
                    }
                }

                Spacer()

                Button { apply() } label: {
                    HStack {
                        Image(systemName: result == .success ? "checkmark" : "bolt.fill")
                        Text(result == .success ? "Đã áp dụng patch" : "Áp dụng patch")
                    }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.techGlow)
                .disabled(isApplying || !rule.hasReplacement || result == .success)
            }
            .padding(20)
            .background(TechBackground())
            .navigationTitle("Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func apply() {
        guard rule.hasReplacement, !isApplying else { return }
        isApplying = true
        result = .idle
        progress = 0

        Task {
            do {
                for step in 1...3 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    progress = Double(step) / 3.0
                }
                try DevicePatchService.setRuleState(true, rule: rule)
                guard DevicePatchService.currentRuleState(for: rule) == true else {
                    throw PatchPackageError.applyFailed
                }
                isApplying = false
                result = .success
            } catch {
                isApplying = false
                result = .failure
            }
        }
    }
}
