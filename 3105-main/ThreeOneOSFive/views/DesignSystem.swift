import SwiftUI

enum AppTheme {
    static let accent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.64, blue: 0.42, alpha: 1.00)
                : UIColor(red: 0.85, green: 0.42, blue: 0.20, alpha: 1.00)
        }
    )
    static let pageBackground = Color(uiColor: .systemBackground)
    static let consoleBackground = Color(uiColor: .secondarySystemBackground)
    static let pageInset: CGFloat = 16

    // MARK: - Tech theme (Home / per-game menu screens)
    static let techBackgroundTop = Color(red: 0.05, green: 0.07, blue: 0.12)
    static let techBackgroundBottom = Color(red: 0.01, green: 0.02, blue: 0.05)
    static let techGlow = Color(red: 0.32, green: 0.86, blue: 0.95)
    static let techCardFill = Color.white.opacity(0.045)
    static let techCardStroke = Color(red: 0.32, green: 0.86, blue: 0.95).opacity(0.30)

    /// Cycled per-row accent so a menu card's items read as distinct switches at a glance,
    /// matching the reference "PROXY MOD MENU" style where each toggle has its own icon color.
    static let rowPalette: [Color] = [
        Color(red: 1.00, green: 0.56, blue: 0.24),
        Color(red: 0.96, green: 0.28, blue: 0.42),
        Color(red: 0.30, green: 0.78, blue: 0.96),
        Color(red: 0.66, green: 0.46, blue: 0.98),
        Color(red: 0.36, green: 0.85, blue: 0.56),
    ]

    static func rowColor(_ index: Int) -> Color {
        rowPalette[index % rowPalette.count]
    }
}

/// A clean dark backdrop used behind the Home and per-game menu screens to give the
/// app a "tech tool" look consistent with the reference designs, instead of the plain system
/// background.
struct TechBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.techBackgroundTop, AppTheme.techBackgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [AppTheme.techGlow.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

private struct TechCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.techCardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.techCardStroke, lineWidth: 1)
            )
            .shadow(color: AppTheme.techGlow.opacity(0.12), radius: 16, y: 0)
    }
}

extension View {
    func techCard() -> some View {
        modifier(TechCardStyle())
    }
}

// MARK: - Toast

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

/// A brief, self-dismissing confirmation pill (e.g. "Đã bật Auto Aim Fix") shown after a
/// successful toggle, so a patch flip has clear positive feedback without the interruption of
/// a blocking alert (alerts stay reserved for failures).
private struct ToastOverlay: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.rowColor(4))
                        Text(toast.text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(AppTheme.techGlow.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.techGlow.opacity(0.25), radius: 18, y: 6)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .task(id: toast.id) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        if self.toast?.id == toast.id {
                            self.toast = nil
                        }
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: toast)
    }
}

extension View {
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastOverlay(toast: message))
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
