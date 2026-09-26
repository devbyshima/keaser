import SwiftUI

/// The full-width white capsule: "Get Started", "Continue",
/// "Enable Notifications".
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: KeaserMetrics.primaryButtonHeight)
            .background(Capsule().fill(Color.white.opacity(isEnabled ? 1 : 0.4)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var keaserPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// An SF Symbol on a rounded dark tile, as in expense rows and the
/// onboarding sample rows.
struct SymbolTile: View {
    let symbol: String
    var size: CGFloat = 40
    var background: Color = .keaserCardRaised

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Centered icon, title and message for empty screens ("No Expenses").
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.white)
                .padding(.bottom, 8)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.keaserSecondaryText)
                .multilineTextAlignment(.center)
            actions
                .padding(.top, 10)
        }
        .frame(maxWidth: 280)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
