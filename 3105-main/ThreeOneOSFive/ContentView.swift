import SwiftUI
import UIKit

// MARK: - License state / API

@MainActor
final class ProxyDemoState: ObservableObject {
    @Published var activatedKey: String? = UserDefaults.standard.string(forKey: "proxy.demo.activatedKey")
    @Published var licenseExpiryText: String? = UserDefaults.standard.string(forKey: "proxy.demo.expiryText")
    @Published var toast: String?
    @Published var isBusy = false
    @Published var isActivated = false
    @Published var activationChecked = false
    @Published var licenseRemainingText: String? = UserDefaults.standard.string(forKey: "proxy.demo.remainingText")

    private var toastTask: Task<Void, Never>?

    private let serverURL: URL = {
        // Chỉ chứa URL API public của license server.
        // Không nhúng tài khoản/mật khẩu Admin vào IPA.
        if let value = Bundle.main.object(forInfoDictionaryKey: "LicenseServerURL") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "http://103.161.16.212:5050")!
    }()

    var maskedKey: String {
        guard let key = activatedKey, !key.isEmpty else { return "••••" }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 8 else { return "••••" }
        if let dash = value.firstIndex(of: "-") {
            let prefixEnd = value.index(after: dash)
            let prefix = String(value[..<prefixEnd])
            let suffix = String(value.suffix(min(5, value.count)))
            return prefix + "••••" + suffix
        }
        return String(value.prefix(min(6, value.count))) + "••••" + String(value.suffix(min(4, value.count)))
    }

    var isLicenseExpired: Bool {
        guard let expiresAt = licenseExpiryText, !expiresAt.isEmpty, expiresAt != "Vĩnh viễn" else {
            return false
        }
        let value = expiresAt.replacingOccurrences(of: "Z", with: "+00:00")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: value)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: value)
        }
        guard let date else { return false }
        return date <= Date()
    }

    var canUseFeatures: Bool {
        isActivated && !isLicenseExpired
    }

    func remainingText(from expiresAt: String?) -> String {
        guard let expiresAt, !expiresAt.isEmpty, expiresAt != "Vĩnh viễn" else {
            return "Vĩnh viễn"
        }

        let value = expiresAt.replacingOccurrences(of: "Z", with: "+00:00")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: value)

        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: value)
        }

        guard let date else { return expiresAt }

        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds == 0 { return "Hết hạn" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "Còn \(days) ngày \(hours) giờ" }
        if hours > 0 { return "Còn \(hours) giờ \(minutes) phút" }
        return "Còn \(max(1, minutes)) phút"
    }

    var deviceID: String {
        // identifierForVendor là ID riêng theo app/vendor trên từng thiết bị.
        // Đây không phải UDID hệ thống của Apple.
        if let vendor = UIDevice.current.identifierForVendor?.uuidString {
            return vendor.uppercased()
        }

        let key = "proxy.demo.deviceID"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }

        let created = UUID().uuidString.uppercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    var deviceName: String {
        UIDevice.current.name
    }

    func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            toast = message
        }

        let current = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, toast == current else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                toast = nil
            }
        }
    }

    func copyDeviceID() {
        UIPasteboard.general.string = deviceID
        showToast("Đã sao chép Device ID")
    }

    func activate(_ key: String) async {
        guard !isBusy else { return }

        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else {
            showToast("⚠️ Vui lòng nhập Key")
            return
        }

        isBusy = true
        defer { isBusy = false }

        // Không thêm delay giả; chỉ chờ phản hồi thật từ License Server.

        do {
            let result = try await LicenseAPI.activate(
                baseURL: serverURL,
                key: cleaned,
                deviceID: deviceID,
                deviceName: deviceName
            )

            guard result.ok else {
                isActivated = false

                let message = result.error ?? result.message ?? "Key không tồn tại"
                let code = (result.code ?? "").uppercased()

                if result.status == "banned" || code == "BANNED" || message.localizedCaseInsensitiveContains("admin") || message.localizedCaseInsensitiveContains("khoá") || message.localizedCaseInsensitiveContains("khóa") {
                    showToast("⚠️ Key đã bị admin Đỗ Hồng Phúc khoá\\ndo vi phạm chính sách quy định hãy liên hệ 0888924907 để được mở!")
                } else if code == "DEVICE_BOUND" || message.lowercased().contains("thiết bị khác") {
                    showToast("Key đã sử dụng cho thiết bị khác")
                } else if result.status == "expired" || message.lowercased().contains("hết hạn") {
                    showToast("Key đã hết hạn")
                } else {
                    showToast(message)
                }
                return
            }

            activatedKey = cleaned
            licenseExpiryText = result.expiresAt ?? "Vĩnh viễn"
            licenseRemainingText = remainingText(from: result.expiresAt)
            isActivated = true

            UserDefaults.standard.set(cleaned, forKey: "proxy.demo.activatedKey")
            UserDefaults.standard.set(licenseExpiryText, forKey: "proxy.demo.expiryText")
            UserDefaults.standard.set(licenseRemainingText, forKey: "proxy.demo.remainingText")

            showToast("Kích hoạt thành công")
        } catch {
            isActivated = false
            showToast("⚠️ Không kết nối được License Server")
        }
    }

    func validateStoredKey() async {
        guard !activationChecked else { return }
        activationChecked = true

        guard let key = activatedKey, !key.isEmpty else {
            isActivated = false
            return
        }

        do {
            let result = try await LicenseAPI.verify(
                baseURL: serverURL,
                key: key
            )

            if result.ok {
                isActivated = true
                licenseExpiryText = result.expiresAt ?? licenseExpiryText
                licenseRemainingText = remainingText(from: result.expiresAt ?? licenseExpiryText)
                UserDefaults.standard.set(licenseExpiryText, forKey: "proxy.demo.expiryText")
                UserDefaults.standard.set(licenseRemainingText, forKey: "proxy.demo.remainingText")
            } else {
                isActivated = false
                activatedKey = nil
                licenseExpiryText = nil
                licenseRemainingText = nil
                UserDefaults.standard.removeObject(forKey: "proxy.demo.activatedKey")
                UserDefaults.standard.removeObject(forKey: "proxy.demo.expiryText")
                UserDefaults.standard.removeObject(forKey: "proxy.demo.remainingText")

                let message = result.error ?? "Key không tồn tại"
                showToast("⚠️ \(message)")
            }
        } catch {
            isActivated = false
            showToast("⚠️ Không kết nối được License Server")
        }
    }

    func clearCache() {
        let fm = FileManager.default
        let cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProxySHOPDHP", isDirectory: true)
        try? fm.removeItem(at: cacheURL)
        showToast("✅ Đã xóa bộ nhớ đệm")
    }

    func checkServer() async {
        do {
            var request = URLRequest(url: serverURL.appendingPathComponent("health"))
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            _ = data
            showToast("✅ License Server đang hoạt động")
        } catch {
            showToast("⚠️ Không kết nối được License Server")
        }
    }
}

struct LicenseAPIResult: Decodable {
    let ok: Bool
    let status: String?
    let error: String?
    let message: String?
    let code: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case ok, status, error, message, code
        case expiresAt = "expires_at"
    }
}

enum LicenseAPI {
    static func activate(
        baseURL: URL,
        key: String,
        deviceID: String,
        deviceName: String
    ) async throws -> LicenseAPIResult {
        var url = baseURL
        if url.path.hasSuffix("/") {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("api/keys/activate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key,
            "udid": deviceID,
            "device_name": deviceName
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(LicenseAPIResult.self, from: data)

        guard (200...499).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return result
    }

    static func verify(baseURL: URL, key: String) async throws -> LicenseAPIResult {
        var url = baseURL
        if url.path.hasSuffix("/") {
            url.deleteLastPathComponent()
        }
        url.appendPathComponent("api/keys/verify")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(LicenseAPIResult.self, from: data)

        guard (200...499).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return result
    }
}

// MARK: - Home

struct ContentView: View {
    @StateObject private var state = ProxyDemoState()

    var body: some View {
        Group {
            if !ExploitSupportPolicy.isCurrentOSSupported {
                UnsupportedOSView()
            } else if state.isActivated {
                ProxyShopHomeView(state: state)
            } else {
                LicenseGateView(state: state, isChangingKey: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .task {
            await state.validateStoredKey()
        }
    }
}

struct UnsupportedOSView: View {
    var body: some View {
        ZStack {
            ProxyBackground()

            VStack(spacing: 18) {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 92, height: 92)
                    .background(Color.red.opacity(0.12), in: Circle())

                Text("iOS Không Được Hỗ Trợ")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Thiết bị đang chạy iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)), chưa nằm trong danh sách tương thích.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Phiên bản hỗ trợ")
                        .font(.headline)

                    ForEach(ExploitSupportPolicy.supportedRanges, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .proxyCard()
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}

struct LicenseGateView: View {
    @ObservedObject var state: ProxyDemoState
    var isChangingKey: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @FocusState private var keyFocused: Bool

    var body: some View {
        ZStack {
            ProxyBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if isChangingKey {
                            HStack {
                                Button {
                                    keyFocused = false
                                    dismiss()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.headline.weight(.semibold))
                                        .frame(width: 42, height: 42)
                                        .background(.white.opacity(0.08), in: Circle())
                                }
                                Spacer()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(isChangingKey ? "Đổi Key" : "ProxyVN SHOP DHP")
                                if !isChangingKey {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.blue)
                                        .accessibilityLabel("Đã xác minh")
                                }
                            }
                                .font(.system(size: 30, weight: .bold))
                            Text(isChangingKey
                                 ? "Nhập key mới để kích hoạt trên thiết bị này."
                                 : "Key được lưu trên thiết bị sau khi kích hoạt.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 12) {
                            InfoLine(icon: "apple.logo", color: .purple, title: "iOS", value: AppInfo.osVersion)
                            InfoLine(icon: "iphone", color: .cyan, title: "Device", value: AppInfo.hardwareDisplayName)

                            HStack(spacing: 10) {
                                Circle()
                                    .fill(ExploitSupportPolicy.isCurrentOSSupported ? Color.green : Color.red)
                                    .frame(width: 12, height: 12)

                                Text(ExploitSupportPolicy.isCurrentOSSupported ? "Có Hỗ Trợ" : "Không Hỗ Trợ")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(ExploitSupportPolicy.isCurrentOSSupported ? Color.green : Color.red)
                            }
                        }
                        .padding(18)
                        .proxyCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Thiết bị này:")
                                .font(.headline)

                            Text(state.deviceID)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                state.copyDeviceID()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Sao chép Device ID")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 10) {
                                TextField("Nhập / dán key...", text: $key)
                                    .focused($keyFocused)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled(true)
                                    .keyboardType(.asciiCapable)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        keyFocused = false
                                        Task { await state.activate(key) }
                                    }

                                Button {
                                    key = UIPasteboard.general.string ?? ""
                                    keyFocused = true
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.title3.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            }

                            Button {
                                keyFocused = false
                                Task { await state.activate(key) }
                            } label: {
                                HStack(spacing: 9) {
                                    if state.isBusy {
                                        ProgressView().tint(.white)
                                    }
                                    Text(state.isBusy ? "Đang kiểm tra..." : "Kích hoạt")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(
                                    LinearGradient(
                                        colors: [.purple, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(state.isBusy)
                        }
                        .padding(18)
                        .proxyCard()
                        .id("license-input")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 46)
                    .padding(.bottom, keyFocused ? 24 : 42)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: keyFocused) { focused in
                    if focused {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("license-input", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let toast = state.toast {
                ToastPill(text: toast)
                    .padding(.top, 48)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: state.activatedKey) { newValue in
            if isChangingKey, newValue != nil, state.isActivated {
                keyFocused = false
                dismiss()
            }
        }
    }
}

struct ProxyShopHomeView: View {
    @ObservedObject var state: ProxyDemoState
    @State private var showSettings = false
    @State private var showChangeKey = false
    @State private var countdownTick = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        brandHeader
                        deviceInfoCard
                        gameCards
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 42)
                    .padding(.bottom, 28)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    compactKeyBar
                }
            }
            .sheet(isPresented: $showSettings) {
                ProxySettingsView(state: state)
            }
            .fullScreenCover(isPresented: $showChangeKey) {
                LicenseGateView(state: state, isChangingKey: true)
            }
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) {
                if let toast = state.toast {
                    ToastPill(text: toast)
                        .padding(.top, 48)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.cyan)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { value in
            countdownTick = value
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text("ProxyVN SHOP DHP")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Đã xác minh")
                }

                Text("Key đã được lưu trên thiết bị")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                showSettings = true
            } label: {
                GearButton()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoLine(icon: "apple.logo", color: .purple, title: "iOS", value: AppInfo.osVersion)
            InfoLine(icon: "iphone", color: .cyan, title: "Device", value: AppInfo.hardwareDisplayName)

            HStack(spacing: 10) {
                Circle()
                    .fill(ExploitSupportPolicy.isCurrentOSSupported ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(ExploitSupportPolicy.isCurrentOSSupported ? "Có Hỗ Trợ" : "Không Hỗ Trợ")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ExploitSupportPolicy.isCurrentOSSupported ? Color.green : Color.red)

                Spacer()

                Text("iOS 16 → 27 beta")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .proxyCard()
    }

    private var compactKeyBar: some View {
        HStack(spacing: 11) {
            Image(systemName: "key.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(colors: [.purple, .cyan],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("KEY \(state.maskedKey)")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                Text(state.remainingText(from: state.licenseExpiryText))
                    .id(countdownTick)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(state.licenseExpiryText == nil ? Color.secondary : Color.green)
            }

            Spacer(minLength: 4)

            Button("Đổi Key") {
                showChangeKey = true
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .shadow(color: .black.opacity(0.25), radius: 14, y: -4)
    }

    private var gameCards: some View {
        HStack(spacing: 12) {
            GameLauncherCard(title: "Free Fire Max", imageName: "FreeFireMax", accent: Color(red: 0.05, green: 0.52, blue: 1.0), bundleID: "com.dts.freefiremax", state: state)
            GameLauncherCard(title: "Free Fire", imageName: "FreeFire", accent: Color(red: 1.0, green: 0.48, blue: 0.08), bundleID: "com.dts.freefireth", state: state)
        }
    }
}

struct GameLauncherCard: View {
    let title: String
    let imageName: String
    let accent: Color
    let bundleID: String
    @ObservedObject var state: ProxyDemoState
    @State private var showGame = false

    var body: some View {
        Button {
            guard state.isActivated else {
                state.showToast("⚠️ Bạn phải nhập Key trước")
                return
            }
            showGame = true
        } label: {
            VStack(spacing: 0) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.top, 22)
                    .padding(.bottom, 18)

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.68), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showGame) {
            GameDemoView(title: title, imageName: imageName, bundleID: bundleID, state: state)
        }
    }
}

// MARK: - Settings

struct ProxySettingsView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showInfo = false
    @State private var showUpdate = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        languageRow
                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            color: .blue,
                            title: language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates",
                            subtitle: language == .vietnamese ? "So sánh với server" : "Compare with server"
                        ) {
                            Task { await state.checkServer() }
                        }
                        SettingsRow(
                            icon: "trash.fill",
                            color: .orange,
                            title: language == .vietnamese ? "Xóa Bộ Nhớ Đệm" : "Clear Cache",
                            subtitle: language == .vietnamese ? "File tạm + ảnh đã tải" : "Temporary files + downloaded images"
                        ) {
                            state.clearCache()
                        }
                        SettingsRow(
                            icon: "square.and.arrow.up",
                            color: .green,
                            title: language == .vietnamese ? "Chia Sẻ Ứng Dụng" : "Share App",
                            subtitle: language == .vietnamese ? "Gửi link tải cho bạn bè" : "Send download link to friends"
                        ) {
                            state.showToast(language == .vietnamese ? "Đã sẵn sàng chia sẻ" : "Ready to share")
                        }
                        SettingsRow(
                            icon: "info.circle.fill",
                            color: .purple,
                            title: language == .vietnamese ? "Thông Tin Ứng Dụng" : "App Information",
                            subtitle: "Version · Device · ID"
                        ) {
                            showInfo = true
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(language == .vietnamese ? "Cài Đặt" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") }
                }
            }
            .sheet(isPresented: $showInfo) { AppInfoView(state: state) }
            .alert(language == .vietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates", isPresented: $showUpdate) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(language == .vietnamese ? "Bạn đang dùng Proxy SHOP DHP V1.0." : "You are using Proxy SHOP DHP V1.0.")
            }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 31))
                .foregroundStyle(.cyan)
                .frame(width: 54, height: 54)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text(language == .vietnamese ? "Cài Đặt" : "Settings")
                    .font(.largeTitle.weight(.bold))
                Text("Proxy SHOP DHP V1.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    private var languageRow: some View {
        HStack {
            Image(systemName: "globe").foregroundStyle(.cyan)
            Text(language == .vietnamese ? "Ngôn Ngữ" : "Language").font(.headline)
            Spacer()
            Picker("", selection: $languageCode) {
                Text("Tiếng Việt").tag(AppLanguage.vietnamese.rawValue)
                Text("English").tag(AppLanguage.english.rawValue)
            }
            .pickerStyle(.menu)
            .tint(.cyan)
        }
        .padding(16)
        .proxyCard()
    }
}

struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white).frame(width: 54, height: 54).background(color.gradient, in: RoundedRectangle(cornerRadius: 15)).shadow(color: color.opacity(0.35), radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .proxyCard()
    }
}

// MARK: - Game demo screen

struct DemoFeature: Identifiable {
    let id = UUID()
    let name: String
    let patchResource: String?
    let description: String
    /// Logical patch destinations shown in the UI. The demo patch engine writes only
    /// inside ProxyVN's private application storage; it never writes to another app's sandbox.
    let logicalTargets: [String]

    init(name: String, patchResource: String?, description: String, logicalTargets: [String] = []) {
        self.name = name
        self.patchResource = patchResource
        self.description = description
        self.logicalTargets = logicalTargets
    }

    var hasBundledPatch: Bool {
        patchResource != nil
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
        DemoFeature(name: "Proxy Aim Body", patchResource: nil, description: "Full đỏ toàn thân", logicalTargets: []),
        DemoFeature(name: "Proxy Aim Neck V1", patchResource: nil, description: "Headshot cổ ít lộ", logicalTargets: []),
        DemoFeature(name: "Proxy Aim Neck V2", patchResource: nil, description: "HeadShot ngực và cổ siêu bá", logicalTargets: []),
        DemoFeature(name: "Proxy Aim Drag", patchResource: nil, description: "Lộ đỉnh đầu, kéo nhẹ là full đỏ", logicalTargets: []),
        DemoFeature(
            name: "Magic V4",
            patchResource: "Magic.3105",
            description: "Bắn xung quay người vẫn tính dame",
            logicalTargets: [
                "com.dts.freefireth/Documents/contentcache/Compulsory/ios/gameassetbundles/",
                "com.dts.freefiremax/Documents/contentcache/Compulsory/ios/gameassetbundles/"
            ]
        )
    ]

    private let locationFeatures: [DemoFeature] = [
        DemoFeature(name: "Định Vị Súng Xanh", patchResource: nil, description: "Hiển thị định vị theo cấu hình"),
        DemoFeature(name: "Định Vị Súng Đỏ", patchResource: nil, description: "Hiển thị định vị theo cấu hình"),
        DemoFeature(name: "Định Vị Súng Hồng", patchResource: nil, description: "Hiển thị định vị theo cấu hình")
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
                                LinearGradient(
                                    colors: [.purple, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)

                        tabBar

                        Group {
                            switch selectedTab {
                            case 0:
                                featureList(features: proxyFeatures)
                            case 1:
                                featureList(features: locationFeatures)
                            default:
                                featureList(features: [])
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
                    Button {
                        dismiss()
                    } label: {
                        CircleIcon(systemName: "chevron.left")
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            GameTab(
                title: "Proxy",
                icon: "bolt.fill",
                active: selectedTab == 0,
                activeColor: .cyan
            ) {
                selectTab(0)
            }

            GameTab(
                title: "Định Vị",
                icon: "location.fill",
                active: selectedTab == 1,
                activeColor: .purple
            ) {
                selectTab(1)
            }

            GameTab(
                title: "Mod NV",
                icon: "person.2.fill",
                active: selectedTab == 2,
                activeColor: .green
            ) {
                selectTab(2)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func selectTab(_ tab: Int) {
        guard selectedTab != tab else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            selectedTab = tab
        }
    }

    private func featureList(features: [DemoFeature]) -> some View {
        VStack(spacing: 10) {
            ForEach(features.indices, id: \.self) { index in
                featureRow(features[index], index: index)
            }

            if features.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                    Text("Mod NV")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .proxyCard()
            }
        }
    }

    private func featureRow(_ feature: DemoFeature, index: Int) -> some View {
        let accent = AppTheme.rowColor(index + selectedTab * 2)
        // Keep the switch interactive so license errors and apply failures can surface
        // as an explicit message instead of looking like a permanently disabled control.
        let canToggle = true

        return HStack(spacing: 12) {
            Image(systemName: enabled.contains(index) ? "checkmark" : "bolt.fill")
                .foregroundStyle(enabled.contains(index) ? Color.green : accent)
                .frame(width: 40, height: 40)
                .background(
                    (enabled.contains(index) ? Color.green : accent).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(busyIndex == index
                     ? "Đang áp dụng patch…"
                     : (failedIndices.contains(index)
                        ? "Feature under maintenance"
                        : feature.description))
                    .font(.caption2)
                    .foregroundStyle(failedIndices.contains(index) ? Color.orange : Color.secondary)

                if feature.hasBundledPatch && !failedIndices.contains(index) {
                    Label("Patch tích hợp sẵn • Magic.3105", systemImage: "shippingbox.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if busyIndex == index {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(accent)
                    .frame(width: 34, height: 34)
            } else {
                if enabled.contains(index) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                } else if failedIndices.contains(index) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }

                Toggle(
                    "",
                    isOn: Binding(
                        get: { enabled.contains(index) },
                        set: { value in
                            handleFeature(feature, index: index, value: value)
                        }
                    )
                )
                .labelsHidden()
                .tint(accent)
                .disabled(!canToggle)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func handleFeature(_ feature: DemoFeature, index: Int, value: Bool) {
        guard busyIndex == nil else { return }

        guard state.canUseFeatures else {
            enabled.remove(index)
            state.showToast(state.isLicenseExpired ? "⚠️ Key đã hết hạn" : "⚠️ Vui lòng kích hoạt Key trước")
            return
        }

        busyIndex = index
        failedIndices.remove(index)

        Task { @MainActor in
            defer {
                withAnimation(.easeOut(duration: 0.16)) {
                    busyIndex = nil
                }
            }

            do {
                if value {
                    guard let resourceName = feature.patchResource else {
                        // No bundled payload: simulate the apply attempt for 2 seconds,
                        // then surface the maintenance state.
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        throw PatchPackageError.invalidProject
                    }

                    // Bundled patch: keep the loading state visible for 4 seconds, then
                    // copy + verify the payload in ProxyVN's private patch workspace.
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                    _ = try DevicePatchService.applyBundledDemoPatch(
                        resourceName: resourceName,
                        featureName: feature.name
                    )
                    enabled.insert(index)
                    failedIndices.remove(index)
                    state.showToast("Đã kích hoạt thành công \(feature.name) ✓")
                } else {
                    enabled.remove(index)
                    failedIndices.remove(index)
                    state.showToast("Đã tắt \(feature.name)")
                }
            } catch {
                enabled.remove(index)
                failedIndices.insert(index)
                state.showToast("⚠️ Feature under maintenance")
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
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))

                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(active ? activeColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                active ? activeColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
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

// MARK: - License UI

struct LicenseKeyView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        LicenseGateView(state: state, isChangingKey: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
    }
}

// MARK: - Policy / Info



struct PolicyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                ProxyBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Image(systemName: "shield.fill").font(.system(size: 42)).foregroundStyle(.cyan).padding(.top, 8)
                        Text("CHÍNH SÁCH & ĐIỀU KHOẢN\nSỬ DỤNG").font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        Text("Vui lòng đọc kỹ trước khi sử dụng dịch vụ").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 14) {
                            PolicySection(icon: "key.fill", color: .cyan, title: "Quy Định License Key & HWID", text: "Mỗi key có thể được giới hạn số thiết bị theo cấu hình server. Ứng dụng dùng Device ID/IDFV thay cho UDID hệ thống mà app không có quyền đọc.")
                            PolicySection(icon: "exclamationmark.shield.fill", color: .orange, title: "Tuyên Bố Miễn Trừ Trách Nhiệm", text: "Người dùng chịu trách nhiệm tuân thủ điều khoản của nền tảng và dịch vụ liên quan.")
                            PolicySection(icon: "lock.fill", color: .green, title: "Hướng Dẫn An Toàn & Bảo Mật", text: "Không nhúng tài khoản admin hoặc mật khẩu server vào IPA/public repository. Chỉ cấu hình URL API license trong app.")
                        }
                        .padding(16).proxyCard()
                        Button { dismiss() } label: { Text("✓ Tôi Đã Hiểu và Đồng Ý").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17).background(LinearGradient(colors: [.purple, .cyan], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain)
                    }
                    .padding(18)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") } } }
            .preferredColorScheme(.dark)
        }
    }
}

struct PolicySection: View {
    let icon: String; let color: Color; let title: String; let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(color).frame(width: 40, height: 40).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12)); Text(title).font(.headline) }
            Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

struct AppInfoView: View {
    @ObservedObject var state: ProxyDemoState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack { ProxyBackground(); VStack(spacing: 14) {
                InfoLine(icon: "app.fill", color: .purple, title: "Ứng dụng", value: "ProxyVN SHOP DHP ✓")
                InfoLine(icon: "number", color: .cyan, title: "Phiên bản", value: "1.0")
                InfoLine(icon: "iphone", color: .cyan, title: "Thiết bị", value: AppInfo.hardwareDisplayName)
                InfoLine(icon: "apple.logo", color: .purple, title: "iOS", value: AppInfo.osVersion)
                InfoLine(icon: "person.crop.circle", color: .green, title: "Device ID", value: state.deviceID)
                Spacer()
            }.padding(18) }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { CircleIcon(systemName: "chevron.left") } } }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Reusable UI

struct ProxyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.025, blue: 0.11),
                    Color(red: 0.012, green: 0.008, blue: 0.025),
                    .black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.purple.opacity(0.18), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct InfoLine: View {
    let icon: String; let color: Color; let title: String; let value: String
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(color).frame(width: 24); Text(title).foregroundStyle(.secondary); Spacer(minLength: 8); Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75) } }
}

struct GearButton: View {
    var body: some View { Image(systemName: "gearshape.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.cyan).frame(width: 52, height: 52).background(Color.white.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)).shadow(color: .cyan.opacity(0.15), radius: 12) }
}

struct CircleIcon: View {
    let systemName: String
    var body: some View { Image(systemName: systemName).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 46, height: 46).background(Color.white.opacity(0.06), in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)) }
}

struct DemoMessageCard: View {
    let title: String; let text: String; let icon: String
    var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.cyan); Text(title).font(.title3.weight(.bold)); Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(28).proxyCard() }
}

struct ToastPill: View {
    let text: String

    private var isWarning: Bool {
        text.contains("⚠️")
            || text.localizedCaseInsensitiveContains("không")
            || text.localizedCaseInsensitiveContains("sai")
            || text.localizedCaseInsensitiveContains("lỗi")
            || text.localizedCaseInsensitiveContains("khoá")
            || text.localizedCaseInsensitiveContains("khóa")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isWarning ? Color.yellow : Color.green)
                .padding(.top, 1)

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }
}

private struct ProxyCardModifier: ViewModifier {
    func body(content: Content) -> some View { content.background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.13), lineWidth: 1)).shadow(color: .purple.opacity(0.08), radius: 18) }
}

extension View { func proxyCard() -> some View { modifier(ProxyCardModifier()) } }
