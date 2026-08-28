import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.appLanguage) private var environmentLanguage
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var toast: ToastMessage?
    @Environment(\.dismiss) private var dismiss

    @State private var showInfo = false
    @State private var showUpdate = false
    @State private var showShare = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private var isVietnamese: Bool {
        language == .vietnamese
    }

    var body: some View {
        NavigationStack {
            settingsContent
                .navigationTitle(isVietnamese ? "Cài Đặt" : "Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(isVietnamese ? "Quay lại" : "Back")
                    }
                }
                .sheet(isPresented: $showInfo) {
                    appInfoSheet
                }
                .sheet(isPresented: $showShare) {
                    ShareSheet(items: ["Proxy SHOP DHP V1.0"])
                }
                .alert(
                    isVietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates",
                    isPresented: $showUpdate
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Proxy SHOP DHP V1.0")
                }
                .toast($toast)
        }
    }

    private var settingsContent: some View {
        ZStack {
            TechBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    headerView
                    languageView
                    actionRows
                }
                .padding(16)
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 30))
                .foregroundStyle(.cyan)
                .frame(width: 54, height: 54)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 16)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(isVietnamese ? "Cài Đặt" : "Settings")
                    .font(.largeTitle.weight(.bold))

                Text("Proxy SHOP DHP V1.0")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var languageView: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(.cyan)

            Text(isVietnamese ? "Ngôn Ngữ" : "Language")
                .font(.headline)

            Spacer(minLength: 0)

            Picker("", selection: $languageCode) {
                Text("Tiếng Việt")
                    .tag(AppLanguage.vietnamese.rawValue)

                Text("English")
                    .tag(AppLanguage.english.rawValue)
            }
            .pickerStyle(.menu)
            .tint(.cyan)
        }
        .padding(16)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private var actionRows: some View {
        VStack(spacing: 0) {
            SettingLine(
                icon: "arrow.triangle.2.circlepath",
                color: .blue,
                title: isVietnamese ? "Kiểm Tra Cập Nhật" : "Check for Updates",
                subtitle: isVietnamese ? "So sánh với server" : "Compare with server"
            ) {
                showUpdate = true
            }

            SettingLine(
                icon: "trash.fill",
                color: .orange,
                title: isVietnamese ? "Xóa Bộ Nhớ Đệm" : "Clear Cache",
                subtitle: isVietnamese
                    ? "File tạm + ảnh đã tải"
                    : "Temporary files + downloaded images"
            ) {
                toast = ToastMessage(
                    text: isVietnamese ? "Đã xóa bộ nhớ đệm" : "Cache cleared"
                )
            }

            SettingLine(
                icon: "square.and.arrow.up",
                color: .green,
                title: isVietnamese ? "Chia Sẻ Ứng Dụng" : "Share App",
                subtitle: isVietnamese
                    ? "Gửi link tải cho bạn bè"
                    : "Send download link to friends"
            ) {
                showShare = true
            }

            SettingLine(
                icon: "info.circle.fill",
                color: .purple,
                title: isVietnamese ? "Thông Tin Ứng Dụng" : "App Information",
                subtitle: "Version · Device · ID"
            ) {
                showInfo = true
            }
        }
        .background(
            Color.white.opacity(0.015),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }

    private var appInfoSheet: some View {
        VStack(spacing: 14) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.purple)

            Text("Proxy SHOP DHP V1.0")
                .font(.title2.weight(.bold))

            Text(AppInfo.hardwareDisplayName)
                .font(.headline)

            Text(AppInfo.osVersion)
                .foregroundStyle(.secondary)

            Text(AppInfo.osBuild)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

private struct SettingLine: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        color.gradient,
                        in: RoundedRectangle(cornerRadius: 15)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
