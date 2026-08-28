import SwiftUI

struct DemoFeature: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let definition: PatchDefinition?
    
    var hasPatch: Bool {
        definition != nil
    }
}

struct GameDemoView: View {
    let title: String
    let imageName: String
    let bundleID: String
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var busyIndex: Int?
    @State private var enabled = Set<Int>()
    @State private var failedIndices = Set<Int>()
    
    private let proxyFeatures: [DemoFeature] = [
        DemoFeature(
            name: "Proxy Aim Body",
            description: "Full đỏ toàn thân",
            definition: PatchDefinitions.forFeatureName("Proxy Aim Body")
        ),
        DemoFeature(
            name: "Proxy Aim Neck V1",
            description: "Headshot cổ ít lộ",
            definition: PatchDefinitions.forFeatureName("Proxy Aim Neck V1")
        ),
        DemoFeature(
            name: "Proxy Aim Neck V2",
            description: "HeadShot ngực và cổ siêu bá",
            definition: PatchDefinitions.forFeatureName("Proxy Aim Neck V2")
        ),
        DemoFeature(
            name: "Proxy Aim Drag",
            description: "Lộ đỉnh đầu, kéo nhẹ là full đỏ",
            definition: nil
        ),
        DemoFeature(
            name: "Magic V4",
            description: "Bắn xung quay người vẫn tính dame",
            definition: PatchDefinitions.forFeatureName("Magic V4")
        )
    ]
    
    private let locationFeatures: [DemoFeature] = [
        DemoFeature(name: "Định Vị Súng Xanh", description: "Hiển thị định vị theo cấu hình", definition: nil),
        DemoFeature(name: "Định Vị Súng Đỏ", description: "Hiển thị định vị theo cấu hình", definition: nil),
        DemoFeature(name: "Định Vị Súng Hồng", description: "Hiển thị định vị theo cấu hình", definition: nil)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .cyan.opacity(0.18), radius: 14, y: 5)
                        
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                        
                        Text(bundleID)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                        
                        Button(action: openGame) {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                Text("MỞ GAME")
                                    .font(.title3.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        tabBar
                        
                        Group {
                            switch selectedTab {
                            case 0: featureList(features: proxyFeatures)
                            case 1: featureList(features: locationFeatures)
                            default: featureList(features: [])
                            }
                        }
                        .id(selectedTab)
                        .transition(.opacity)
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            GameTab(title: "Proxy", icon: "bolt.fill", active: selectedTab == 0, activeColor: .cyan) { selectTab(0) }
            GameTab(title: "Định Vị", icon: "location.fill", active: selectedTab == 1, activeColor: .purple) { selectTab(1) }
            GameTab(title: "Mod NV", icon: "person.2.fill", active: selectedTab == 2, activeColor: .green) { selectTab(2) }
        }
        .padding(4)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }
    
    private func selectTab(_ tab: Int) {
        guard selectedTab != tab else { return }
        withAnimation(.easeOut(duration: 0.18)) { selectedTab = tab }
    }
    
    private func featureList(features: [DemoFeature]) -> some View {
        VStack(spacing: 10) {
            ForEach(features.indices, id: \.self) { index in
                featureRow(features[index], index: index)
            }
            if features.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.fill").font(.system(size: 26)).foregroundStyle(.green)
                    Text("Mod NV").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .proxyCard()
            }
        }
    }
    
    private func featureRow(_ feature: DemoFeature, index: Int) -> some View {
        let accent = AppTheme.rowColor(index + selectedTab * 2)
        return HStack(spacing: 12) {
            Image(systemName: enabled.contains(index) ? "checkmark" : "bolt.fill")
                .foregroundStyle(enabled.contains(index) ? Color.green : accent)
                .frame(width: 40, height: 40)
                .background((enabled.contains(index) ? Color.green : accent).opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.name).font(.headline).lineLimit(1)
                Text(failedIndices.contains(index) ? "⚠️ Chức năng đang bảo trì" : feature.description)
                    .font(.caption2)
                    .foregroundStyle(failedIndices.contains(index) ? Color.orange : Color.secondary)
            }
            
            Spacer(minLength: 8)
            
            if busyIndex == index {
                ProgressView().progressViewStyle(.circular).tint(accent).frame(width: 34, height: 34)
            } else {
                if enabled.contains(index) {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                } else if failedIndices.contains(index) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.red)
                }
                
                Toggle("", isOn: Binding(
                    get: { enabled.contains(index) },
                    set: { value in handleFeatureToggle(feature, index: index, value: value) }
                ))
                .labelsHidden()
                .tint(accent)
                .disabled(!feature.hasPatch)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(Rectangle())
    }
    
    private func handleFeatureToggle(_ feature: DemoFeature, index: Int, value: Bool) {
        guard busyIndex == nil else { return }
        guard state.canUseFeatures else {
            enabled.remove(index)
            state.showToast(state.isLicenseExpired ? "⚠️ Key đã hết hạn" : "⚠️ Vui lòng kích hoạt Key trước")
            return
        }
        guard let definition = feature.definition else {
            enabled.remove(index)
            failedIndices.insert(index)
            state.showToast("⚠️ Chức năng chưa có patch")
            return
        }
        
        busyIndex = index
        failedIndices.remove(index)
        
        Task { @MainActor in
            defer {
                withAnimation(.easeOut(duration: 0.16)) { busyIndex = nil }
            }
            
            let success = RealPatchManager.applyPatchFromDefinition(
                definition: definition,
                gameBundleID: bundleID,
                isOn: value
            )
            
            if success {
                if value {
                    enabled.insert(index)
                    state.showToast("✅ Đã kích hoạt \(feature.name)")
                } else {
                    enabled.remove(index)
                    state.showToast("✅ Đã tắt \(feature.name)")
                }
                failedIndices.remove(index)
            } else {
                enabled.remove(index)
                failedIndices.insert(index)
                state.showToast("⚠️ Không thể áp dụng patch cho \(feature.name)")
            }
        }
    }
    
    private func openGame() {
        let scheme = title == "Free Fire Max" ? "freefiremax" : "freefire"
        guard let url = URL(string: "\(scheme)://") else { return }
        UIApplication.shared.open(url)
    }
}

struct GameTab: View {
    let title: String
    let icon: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                Text(title).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(active ? activeColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(active ? activeColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(activeColor.opacity(0.42), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
